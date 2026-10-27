#!/usr/bin/env bats
# Ciclo backup -> restore con datos sinteticos, en aislamiento.
#
# Nada de este test toca el kit real: se copia el codigo a un directorio
# temporal, con su propio .env sintetico, y el docker es un stub que no
# levanta ningun contenedor. Lo que se prueba es el contrato, no el runtime.
bats_require_minimum_version 1.5.0

setup() {
  KIT="$BATS_TEST_TMPDIR/kit"
  mkdir -p "$KIT/scripts" "$BATS_TEST_TMPDIR/bin"
  cp "$BATS_TEST_DIRNAME/../scripts/backup.py" "$BATS_TEST_DIRNAME/../scripts/restore.py" "$KIT/scripts/"
  cp "$BATS_TEST_DIRNAME/../compose.yaml" "$KIT/"
  printf 'COMPOSE_PROJECT_NAME=hefesto-monitor-prueba\nDATA_VOLUME=hefesto-monitor-prueba-data\n' > "$KIT/.env"

  cat > "$BATS_TEST_TMPDIR/bin/docker" <<'STUB'
#!/usr/bin/env bash
# Stub de docker: no toca ningun contenedor.
set -uo pipefail
printf '%s\n' "$*" >> "${STUB_DOCKER_LOG:-/dev/null}"

modo=""
anterior=""
for a in "$@"; do
  if [ "$anterior" = "--entrypoint" ]; then modo="$a"; fi
  anterior="$a"
done

# compose ps -q kuma: si el servicio esta arriba.
case " $* " in
  *" ps "*)
    [ "${STUB_DOCKER_PS:-vacio}" = "vacio" ] && exit 0
    printf 'kuma-falso\n'
    exit 0
    ;;
esac

if [ "$modo" = "tar" ]; then
  case " $* " in
    # Restauracion: se consume la entrada y no se produce salida.
    *" -xzf "*) cat >/dev/null; exit 0 ;;
  esac
  d="$(mktemp -d)"
  mkdir -p "$d/data"
  printf 'kuma-db-sintetico\n' > "$d/data/kuma.db"
  printf 'config-sintetica\n' > "$d/data/config.txt"
  tar -czf - -C "$d/data" .
  rm -rf "$d"
  exit 0
fi

if [ "$modo" = "find" ]; then
  [ "${STUB_DOCKER_VOLUMEN:-vacio}" = "lleno" ] && printf 'kuma.db\n'
  exit 0
fi

exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/docker"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export STUB_DOCKER_LOG="$BATS_TEST_TMPDIR/docker.log"
  export STUB_DOCKER_PS="corriendo" STUB_DOCKER_VOLUMEN="vacio"
  export HEFESTO_MONITOR_LOG_DIR="$BATS_TEST_TMPDIR/logs"
  export DESTINO="$BATS_TEST_TMPDIR/backups"
}

respaldo_creado() {
  find "$DESTINO" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1
}

@test "backup.py exige .env antes de hacer nada" {
  rm -f "$KIT/.env"
  run python3 "$KIT/scripts/backup.py" --destino "$DESTINO"
  echo "status=$status output=$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Falta .env"* ]]
}

@test "backup.py crea data.tar.gz, SHA256SUMS y manifest.json con status completed" {
  run python3 "$KIT/scripts/backup.py" --destino "$DESTINO"
  echo "status=$status output=$output"
  [ "$status" -eq 0 ]
  carpeta="$(respaldo_creado)"
  [ -n "$carpeta" ]
  [ -f "$carpeta/data.tar.gz" ]
  [ -f "$carpeta/SHA256SUMS" ]
  [ -f "$carpeta/manifest.json" ]
  run grep -o '"status": *"completed"' "$carpeta/manifest.json"
  [ "$status" -eq 0 ]
}

@test "el .env NUNCA queda en claro en el arbol de respaldos" {
  run python3 "$KIT/scripts/backup.py" --destino "$DESTINO"
  [ "$status" -eq 0 ]
  run bash -c "find '$DESTINO' -name '.env' -o -name '*.env' | head -5"
  echo "$output"
  [ -z "$output" ]
  # Tampoco puede quedar el valor de una variable suelta.
  run bash -c "grep -rl 'hefesto-monitor-prueba-data' '$DESTINO' 2>/dev/null | head -5"
  echo "$output"
  [ -z "$output" ]
}

@test "env.vars trae solo nombres de variable, nunca valores" {
  run python3 "$KIT/scripts/backup.py" --destino "$DESTINO"
  [ "$status" -eq 0 ]
  carpeta="$(respaldo_creado)"
  [ -f "$carpeta/env.vars" ]
  run cat "$carpeta/env.vars"
  [[ "$output" == *"COMPOSE_PROJECT_NAME"* ]]
  [[ "$output" == *"DATA_VOLUME"* ]]
  [[ "$output" != *"hefesto-monitor-prueba-data"* ]]
}

@test "con AGE_RECIPIENTE el .env sale cifrado y age lo puede descifrar" {
  command -v age >/dev/null || skip "age no instalado"
  command -v age-keygen >/dev/null || skip "age-keygen no instalado"
  # age-keygen imprime la clave publica por stderr, no por stdout.
  AGE_RECIPIENTE="$(age-keygen -o "$BATS_TEST_TMPDIR/age.key" 2>&1 | grep -o 'age1[a-z0-9]*' | head -1)"
  [ -n "$AGE_RECIPIENTE" ]
  export AGE_RECIPIENTE

  run python3 "$KIT/scripts/backup.py" --destino "$DESTINO"
  echo "status=$status output=$output"
  [ "$status" -eq 0 ]
  carpeta="$(respaldo_creado)"
  [ -f "$carpeta/env.age" ]
  # El cifrado no puede contener el valor en claro.
  run bash -c "grep -c 'hefesto-monitor-prueba-data' '$carpeta/env.age' || true"
  [ "${output%% *}" = "0" ]
  # Y se puede descifrar con la clave del receptor.
  run bash -c "age -d -i '$BATS_TEST_TMPDIR/age.key' '$carpeta/env.age'"
  echo "$output"
  [[ "$output" == *"DATA_VOLUME=hefesto-monitor-prueba-data"* ]]
}

@test "sin age no se degrada a texto plano: el respaldo falla" {
  run python3 - "$KIT/scripts/backup.py" <<'PY'
import importlib.util, os, pathlib, sys
spec = importlib.util.spec_from_file_location('backup', sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
os.environ['PATH'] = '/nonexistent'
try:
    mod.cifrar_env(pathlib.Path('/tmp'), pathlib.Path('/tmp/x.age'), 'age1prueba')
except SystemExit as exc:
    print('OK:', exc)
    sys.exit(0)
print('no fallo: se degrado a texto plano')
sys.exit(1)
PY
  echo "status=$status output=$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK:"* ]]
}

@test "restore.py rechaza un manifiesto con version distinta" {
  run python3 "$KIT/scripts/backup.py" --destino "$DESTINO"
  [ "$status" -eq 0 ]
  carpeta="$(respaldo_creado)"
  python3 - "$carpeta/manifest.json" <<'PY'
import json, sys
ruta = sys.argv[1]
manifiesto = json.load(open(ruta))
manifiesto['version'] = '9.9.9'
json.dump(manifiesto, open(ruta, 'w'), indent=2)
PY
  run python3 "$KIT/scripts/restore.py" "$carpeta"
  echo "status=$status output=$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Version/manifest/checksum no valido"* ]]
}

@test "restore.py se niega a sobrescribir un volumen no vacio" {
  run python3 "$KIT/scripts/backup.py" --destino "$DESTINO"
  [ "$status" -eq 0 ]
  carpeta="$(respaldo_creado)"
  # Destino detenido pero con contenido: no se pisa lo que hay.
  export STUB_DOCKER_PS="vacio" STUB_DOCKER_VOLUMEN="lleno"
  run python3 "$KIT/scripts/restore.py" "$carpeta"
  echo "status=$status output=$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Volumen destino no vacio"* ]]
}

@test "el ciclo completo deja auditoria con el sha256 verificado" {
  run python3 "$KIT/scripts/backup.py" --destino "$DESTINO"
  [ "$status" -eq 0 ]
  carpeta="$(respaldo_creado)"
  export STUB_DOCKER_PS="vacio" STUB_DOCKER_VOLUMEN="vacio"
  run python3 "$KIT/scripts/restore.py" "$carpeta"
  echo "status=$status output=$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Datos restaurados"* ]]

  [ -f "$HEFESTO_MONITOR_LOG_DIR/restore.log" ]
  run cat "$HEFESTO_MONITOR_LOG_DIR/restore.log"
  echo "$output"
  [[ "$output" == *'"accion": "restore"'* ]]
  [[ "$output" == *'"resultado": "ok"'* ]]
  digest="$(cut -d' ' -f1 "$carpeta/SHA256SUMS")"
  [[ "$output" == *"$digest"* ]]
}

@test "restore.py se niega a restaurar con el destino en ejecucion" {
  run python3 "$KIT/scripts/backup.py" --destino "$DESTINO"
  [ "$status" -eq 0 ]
  carpeta="$(respaldo_creado)"
  export STUB_DOCKER_PS="corriendo"
  run python3 "$KIT/scripts/restore.py" "$carpeta"
  echo "status=$status output=$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Destino en ejecucion"* ]]
}
