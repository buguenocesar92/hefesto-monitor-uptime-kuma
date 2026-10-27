#!/usr/bin/env bash
# scripts/coolify-check.sh
# Verifica que compose.yaml cumple el contrato de Coolify: no expone nada al
# host ni usa capacidades que se salten Traefik, y mantiene los nombres
# parametrizados para que Coolify pueda poner el nombre de proyecto.
#
# Salida: 0 si el compose cumple, 1 si no. Imprime los motivos por servicio.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/compose.yaml"

if [[ ! -f "$COMPOSE_FILE" ]]; then
    printf 'ERROR: no existe %s\n' "$COMPOSE_FILE" >&2
    exit 1
fi

command -v docker >/dev/null 2>&1 || { printf 'ERROR: falta docker\n' >&2; exit 1; }
command -v jq    >/dev/null 2>&1 || { printf 'ERROR: falta jq\n'    >&2; exit 1; }

# Recoger todas las variables ${VAR...} del compose y crear un .env temporal
# con valores ficticios no secretos. Las que parezcan URL/host van a .invalid.
TMP_ENV="$(mktemp)"
trap 'rm -f "$TMP_ENV" "$TMP_ENV.vars"' EXIT

grep -oE '\$\{[A-Z_][A-Z0-9_]*(:[-=?+][^}]*)?\}' "$COMPOSE_FILE" \
    | sed -E 's/^\$\{([A-Z_][A-Z0-9_]*).*/\1/' \
    | sort -u > "$TMP_ENV.vars" || true

while read -r var; do
    [[ -z "$var" ]] && continue
    case "$var" in
        *URL*|*ENDPOINT*|*HOST*) printf '%s=https://ejemplo.invalid\n' "$var" >> "$TMP_ENV" ;;
        *)                        printf '%s=x1234567890abcdef\n'       "$var" >> "$TMP_ENV" ;;
    esac
done < "$TMP_ENV.vars"

# Renderizar el compose con el .env temporal. stderr se descarta para no
# contaminar el JSON que consume jq.
if ! RENDERED="$(docker compose --project-directory "$REPO_ROOT" \
        -f "$COMPOSE_FILE" --env-file "$TMP_ENV" config --format json 2>/dev/null)"; then
    printf 'ERROR: no se pudo renderizar %s\n' "$COMPOSE_FILE" >&2
    exit 1
fi

# Contrato 1: nada que salte Traefik ni dé poder sobre el host.
# Aplica a servicios sin profiles (este repo no usa profiles).
# El REPO_ROOT se pasa como variable de entorno para que jq pueda chequear
# que ninguna ruta de bind quede fuera del repositorio.
read -r -d '' JQ_QUERY <<'JQE' || true
.services
| to_entries[]
| select((.value.profiles // null) == null)
| .key as $svc
| (.value.volumes // []) as $vols
| ($vols | map(select(.source != null and (.source | test("docker.sock")))) | length) as $dockersock
| ($vols | map(select(.type == "bind" and (.source | type == "string") and (.source | startswith("/")) and ((.source == env.REPO_ROOT or (.source | startswith(env.REPO_ROOT + "/"))) | not))) | length) as $external_binds
| [
    (select((.value.ports // [])        | length > 0) | "ports publicado al host"),
    (select(.value.container_name        != null)       | "container_name fijo"),
    (select(.value.privileged            == true)       | "privileged"),
    (select((.value.cap_add // [])       | length > 0) | "cap_add"),
    (select((.value.devices // [])       | length > 0) | "devices"),
    (select(.value.network_mode          == "host")     | "network_mode host"),
    (select(.value.pid                   == "host")     | "pid host"),
    (select(.value.ipc                   == "host")     | "ipc host"),
    (select((.value.security_opt // [])  | any(. == "unconfined" or test("unconfined"))) | "security_opt unconfined"),
    (select($dockersock    > 0) | "bind docker.sock"),
    (select($external_binds > 0) | "bind fuera del repo")
  ]
| map(select(. != null)) as $violations
| select(($violations | length) > 0)
| [$svc, ($violations | join("; "))]
| @tsv
JQE

failures=()
if ! JQ_OUT="$(printf '%s' "$RENDERED" | REPO_ROOT="$REPO_ROOT" jq -r "$JQ_QUERY")"; then
    printf 'ERROR: jq falló al evaluar el contrato\n' >&2
    exit 1
fi
while IFS=$'\t' read -r svc motivos; do
    [[ -z "$svc" ]] && continue
    failures+=("${svc}: ${motivos}")
done <<< "$JQ_OUT"

# Contrato 2: nombres parametrizados (no literales fijos).
# a) name: a nivel raíz no debe tener valor literal (con o sin comillas,
#    y aunque el valor empiece por dígito: solo aceptamos ${VAR}).
if grep -E '^name:[[:space:]]+["'\'']?[^$"'\''[:space:]]' "$COMPOSE_FILE" >/dev/null; then
    failures+=('compose: name fijo a nivel raíz (debe ser ${VAR})')
fi

# b) redes/volúmenes con name: literal (no ${...}).
if grep -nE '^[[:space:]]+name:[[:space:]]+["'\'']?[^$"'\''[:space:]]' "$COMPOSE_FILE" >/dev/null; then
    failures+=('compose: red o volumen con name: literal (debe ser ${VAR})')
fi

# Contrato 3: el servicio que expone el puerto no corre con privilegios.
# El contrato de Coolify prohibe cap_add, asi que la alternativa a una
# capacidad no es sumar una capacidad: es correr como usuario que no la
# necesita, sin capacidades y sin poder ganarlas.
read -r -d '' JQ_QUERY3 <<'JQE' || true
.services
| to_entries[]
| select((.value.profiles // null) == null)
| select((.value.expose // []) | length > 0)
| .key as $svc
| [
    (select(((.value.user // "") | tostring) as $u | ($u == "" or $u == "0" or $u == "0:0" or $u == "root")) | "corre como root"),
    (select(((.value.security_opt // []) | map(tostring) | map(select(. == "no-new-privileges:true" or . == "no-new-privileges")) | length) == 0) | "sin no-new-privileges"),
    (select(((.value.cap_drop // []) | map(tostring | ascii_downcase) | map(select(. == "all")) | length) == 0) | "sin cap_drop ALL")
  ]
| map(select(. != null)) as $violations
| select(($violations | length) > 0)
| [$svc, ($violations | join("; "))]
| @tsv
JQE

if ! JQ_OUT3="$(printf '%s' "$RENDERED" | jq -r "$JQ_QUERY3")"; then
    printf 'ERROR: jq fallo al evaluar el contrato de privilegios\n' >&2
    exit 1
fi
while IFS=$'\t' read -r svc motivos; do
    [[ -z "$svc" ]] && continue
    failures+=("${svc}: ${motivos}")
done <<< "$JQ_OUT3"

if [[ ${#failures[@]} -gt 0 ]]; then
    printf 'Falla: compose no conforme al contrato de Coolify:\n' >&2
    printf '  - %s\n' "${failures[@]}" >&2
    exit 1
fi

printf 'OK: compose conforme al contrato de Coolify.\n'