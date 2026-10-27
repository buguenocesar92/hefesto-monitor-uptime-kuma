#!/usr/bin/env bats
# Contrato del compose de Uptime Kuma.
#
# El compose no solo tiene que funcionar: tiene que cumplir el contrato de
# Coolify (nada published al host, nada de capacidades, nada de poder sobre el
# host) y el de menor privilegio (el servicio que expone el puerto corre como
# usuario sin privilegios, sin capacidades y sin poder ganar mas).
bats_require_minimum_version 1.5.0

COMPOSE="$BATS_TEST_DIRNAME/../compose.yaml"

render() {
  # Renderiza el compose con valores ficticios y lo devuelve en JSON.
  env -i PATH="$PATH" HOME="$HOME" \
    COMPOSE_PROJECT_NAME=hefesto-monitor-prueba \
    DATA_VOLUME=hefesto-monitor-prueba-data \
    docker compose -f "$COMPOSE" config --format json 2>/dev/null
}

@test "el compose renderiza" {
  command -v docker >/dev/null || skip "docker no disponible"
  run bash -c "cd '$BATS_TEST_DIRNAME/..' && COMPOSE_PROJECT_NAME=prueba DATA_VOLUME=prueba-data docker compose -f compose.yaml config --quiet"
  echo "status=$status output=$output"
  [ "$status" -eq 0 ]
}

@test "la imagen esta fijada por digest" {
  run grep -cE 'image: louislam/uptime-kuma:[0-9.]+-slim@sha256:[0-9a-f]{64}' "$COMPOSE"
  [ "${output%% *}" -ge 1 ]
}

@test "el servicio que expone el puerto corre como usuario sin privilegios" {
  run python3 - "$COMPOSE" <<'PY'
import sys, yaml
compose = yaml.safe_load(open(sys.argv[1]))
servicios = compose.get('services', {})
problemas = []
for nombre, servicio in servicios.items():
    if not (servicio.get('expose') or []):
        continue
    usuario = str(servicio.get('user', '')).strip()
    if usuario in ('', '0', '0:0', 'root'):
        problemas.append(f'{nombre}: corre como root ({usuario!r})')
    if 'no-new-privileges:true' not in [str(o) for o in (servicio.get('security_opt') or [])]:
        problemas.append(f'{nombre}: sin no-new-privileges')
    if 'ALL' not in [str(c).upper() for c in (servicio.get('cap_drop') or [])]:
        problemas.append(f'{nombre}: sin cap_drop ALL')
print('; '.join(problemas) if problemas else 'OK')
sys.exit(1 if problemas else 0)
PY
  echo "status=$status output=$output"
  [ "$status" -eq 0 ]
}

@test "ningun servicio usa cap_add" {
  # cap_add rompe el contrato de Coolify. Si alguna vez hiciera falta una
  # capacidad, la solucion es un usuario sin privilegios, no una capacidad.
  run python3 - "$COMPOSE" <<'PY'
import sys, yaml
compose = yaml.safe_load(open(sys.argv[1]))
problemas = []
for nombre, servicio in compose.get('services', {}).items():
    if servicio.get('cap_add'):
        problemas.append(f'{nombre}: cap_add={servicio["cap_add"]}')
    if servicio.get('privileged'):
        problemas.append(f'{nombre}: privileged')
print('; '.join(problemas) if problemas else 'OK')
sys.exit(1 if problemas else 0)
PY
  echo "status=$status output=$output"
  [ "$status" -eq 0 ]
}

@test "ningun servicio publica puertos al host" {
  run python3 - "$COMPOSE" <<'PY'
import sys, yaml
compose = yaml.safe_load(open(sys.argv[1]))
problemas = []
for nombre, servicio in compose.get('services', {}).items():
    if servicio.get('ports'):
        problemas.append(f'{nombre}: ports={servicio["ports"]}')
print('; '.join(problemas) if problemas else 'OK')
sys.exit(1 if problemas else 0)
PY
  echo "status=$status output=$output"
  [ "$status" -eq 0 ]
}

@test "el verificador de contrato de Coolify acepta el compose" {
  command -v docker >/dev/null || skip "docker no disponible"
  command -v jq >/dev/null || skip "jq no disponible"
  run bash "$BATS_TEST_DIRNAME/../scripts/coolify-check.sh"
  echo "status=$status output=$output"
  [ "$status" -eq 0 ]
}
