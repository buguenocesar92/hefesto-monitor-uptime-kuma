#!/usr/bin/env bats
# Finales de linea y sintaxis.
#
# El CRLF en un script de shell rompe la ejecucion de forma silenciosa: la
# primera linea se convierte en "/bin/bash\r" y el error aparece lejos de la
# causa. Este repo ya no tiene CRLF; el test lo deja fijado.
bats_require_minimum_version 1.5.0

@test "ningun archivo de scripts/ tiene CR" {
  # Solo el codigo fuente: __pycache__/*.pyc es binario y esta en .gitignore.
  run bash -c "grep -rlP '\\x0d' --include='*.py' --include='*.sh' '$BATS_TEST_DIRNAME/../scripts/' 2>/dev/null || true"
  echo "$output"
  [ -z "$output" ]
}

@test "todo script de shell pasa bash -n" {
  for f in "$BATS_TEST_DIRNAME"/../scripts/*.sh; do
    run bash -n "$f"
    [ "$status" -eq 0 ]
  done
}

@test "todo script de python compila" {
  run python3 -m py_compile "$BATS_TEST_DIRNAME"/../scripts/*.py
  echo "$output"
  [ "$status" -eq 0 ]
}
