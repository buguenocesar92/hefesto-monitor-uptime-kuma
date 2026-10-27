#!/usr/bin/env python3
"""Restaura solo en volumen vacio. No arranca el servidor ni envia alertas.

Contrato del respaldo (normativo, ver docs/CONTRATO-RESPALDO.md): antes de
restaurar se validan el manifiesto, el checksum y las rutas del tar, y se exige
que el volumen destino este vacio. Cada restauracion deja un rastro de
auditoria en logs/restore.log: origen, sha256 verificado, destino y resultado.
"""
import datetime
import hashlib
import json
import os
import subprocess
import sys
import tarfile
from pathlib import Path, PurePosixPath

RAIZ = Path(__file__).resolve().parents[1]
VERSION = '2.5.6'


def dc(*args, **kw):
    return subprocess.run(['docker', 'compose', *args], check=True, **kw)


def escribir_auditoria(registro, directorio=None):
    """Anade una linea de auditoria. Nunca se registran valores de secretos."""
    directorio = Path(directorio or os.environ.get('HEFESTO_MONITOR_LOG_DIR') or (RAIZ / 'logs'))
    directorio.mkdir(parents=True, exist_ok=True)
    with (directorio / 'restore.log').open('a', encoding='utf-8') as fh:
        fh.write(json.dumps(registro, ensure_ascii=False) + '\n')


def validar_respaldo(backup):
    """Valida manifiesto, checksum y rutas del tar. Devuelve el manifiesto.

    Levanta SystemExit con un mensaje claro si algo no cuadra: el respaldo no
    se restaura a medias.
    """
    backup = Path(backup)
    manifiesto = json.loads((backup / 'manifest.json').read_text())
    with (backup / 'data.tar.gz').open('rb') as fh:
        digest = hashlib.file_digest(fh, 'sha256').hexdigest()
    if manifiesto.get('status') != 'completed' or manifiesto.get('version') != VERSION \
            or digest != manifiesto.get('sha256'):
        raise SystemExit('Version/manifest/checksum no valido')
    with tarfile.open(backup / 'data.tar.gz', 'r:gz') as tar:
        for entrada in tar:
            ruta = PurePosixPath(entrada.name)
            if ruta.is_absolute() or '..' in ruta.parts or not (entrada.isfile() or entrada.isdir()):
                raise SystemExit('Archivo con rutas o tipos no permitidos')
    return manifiesto


def restaurar(backup, raiz=None, directorio_log=None):
    """Restaura el respaldo en el volumen del proyecto. No arranca el servicio."""
    raiz = Path(raiz) if raiz else RAIZ
    os.chdir(raiz)
    if not (raiz / '.env').is_file():
        raise SystemExit('Configurar primero el proyecto de destino con scripts/configure.py')

    backup = Path(backup).resolve()
    manifiesto = validar_respaldo(backup)
    digest = manifiesto['sha256']

    if dc('ps', '--status', 'running', '-q', 'kuma', capture_output=True, text=True).stdout.strip():
        raise SystemExit('Destino en ejecucion. Usar instancia nueva y detenerla primero.')

    # Nunca vaciar ni sobrescribir datos existentes. Detectar tambien archivos ocultos.
    probe = dc('run', '--rm', '--no-deps', '-T', '--user', '0:0', '--entrypoint', 'find',
               'kuma', '/app/data', '-mindepth', '1', '-maxdepth', '1',
               capture_output=True, text=True)
    if probe.stdout.strip():
        raise SystemExit('Volumen destino no vacio: restauracion cancelada.')

    with (backup / 'data.tar.gz').open('rb') as origen:
        dc('run', '--rm', '--no-deps', '-T', '--user', '0:0', '--entrypoint', 'tar',
           'kuma', '-xzf', '-', '-C', '/app/data', stdin=origen)

    escribir_auditoria({
        'accion': 'restore',
        'origen': str(backup),
        'sha256_verificado': digest,
        'destino_volumen': 'data',
        'resultado': 'ok',
        'timestamp_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }, directorio_log)
    return backup


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if len(argv) != 1:
        raise SystemExit('Uso: python3 scripts/restore.py /ruta/respaldo')
    restaurar(argv[0])
    print('Datos restaurados. Servicio NO iniciado. Revisa notificaciones y aislamiento antes de arrancar.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
