#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v docker >/dev/null
python3 --version
docker compose version
docker compose config --quiet
docker compose ps
printf 'Revision de configuracion completada. Continuar con docs/ACEPTACION.md.\n'
