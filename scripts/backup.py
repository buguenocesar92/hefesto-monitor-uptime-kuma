#!/usr/bin/env python3
"""Respaldo coherente de todo /app/data; requiere Docker Compose y tiempo de parada.

Contrato del respaldo (normativo, ver docs/CONTRATO-RESPALDO.md):

  <destino>/data.tar.gz    dump de /app/data (contiene kuma.db)
  <destino>/SHA256SUMS     sha256 de data.tar.gz
  <destino>/manifest.json  software, version, database, sha256, status
  <destino>/env.vars       SOLO los nombres de variable del .env, nunca los valores
  <destino>/env.age       el .env cifrado con age, SOLO si hay receptor configurado

El .env NUNCA se copia en claro: es lo que hace que un respaldo copiado a otra
maquina sea una credencial tendida. Si no hay receptor age configurado, el
respaldo sale sin el .env y lo dice en el manifiesto.
"""
import argparse
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
VERSION = '2.5.6'


def dc(*args, **kwargs):
    """docker compose ... con check=True."""
    return subprocess.run(['docker', 'compose', *args], check=True, **kwargs)


def nombres_env(ruta):
    """Nombres de variable del .env. Nunca los valores."""
    nombres = []
    if not Path(ruta).is_file():
        return nombres
    for linea in Path(ruta).read_text(encoding='utf-8', errors='replace').splitlines():
        linea = linea.strip()
        if not linea or linea.startswith('#') or '=' not in linea:
            continue
        nombres.append(linea.split('=', 1)[0].strip())
    return nombres


def cifrar_env(origen, destino, receptor):
    """Cifra el .env con age. Devuelve True si quedo cifrado.

    La clave privada del receptor es un insumo externo: vive en el gestor de
    secretos del cliente (Infisical, Vaultwarden) o en un sobre cifrado fuera
    del servidor. Este script solo usa la publica.
    """
    if not receptor:
        return False
    if shutil.which('age') is None:
        raise SystemExit('ERROR: hay receptor age configurado pero age no esta instalado. '
                         'Sin age el .env no se copia: no se degrada a texto plano.')
    with open(origen, 'rb') as entrada, open(destino, 'wb') as salida:
        subprocess.run(['age', '-r', receptor], stdin=entrada, stdout=salida, check=True)
    return True


def construir_respaldo(destino, raiz=None):
    """Genera el respaldo completo en `destino`. Devuelve la ruta.

    Requiere el servicio en ejecucion: para que el dump de SQLite sea coherente
    hay que detener el contenedor, y solo se detiene lo que ya estaba arriba.
    """
    raiz = Path(raiz) if raiz else RAIZ
    os.chdir(raiz)
    os.umask(0o077)
    if not (raiz / '.env').is_file():
        raise SystemExit('Falta .env')

    activo = dc('ps', '--status', 'running', '-q', 'kuma', capture_output=True, text=True).stdout.strip()
    if not activo:
        raise SystemExit('kuma no esta en ejecucion en este contexto Compose. Verifica proyecto/recurso.')

    destino = Path(destino)
    destino.mkdir(parents=True, exist_ok=False)
    archivo = destino / 'data.tar.gz'
    try:
        dc('stop', 'kuma')
        with archivo.open('wb') as salida:
            dc('run', '--rm', '--no-deps', '-T', '--user', '0:0', '--entrypoint', 'tar',
               'kuma', '-czf', '-', '-C', '/app/data', '.', stdout=salida)
        with tarfile.open(archivo, 'r:gz') as tar:
            if not any(m.name.endswith('kuma.db') for m in tar):
                raise RuntimeError('No se encontro kuma.db; revisar tipo DB e instalacion')

        # El .env no se copia en claro: solo sus nombres, y cifrado si hay receptor.
        (destino / 'env.vars').write_text(
            ''.join(n + '\n' for n in nombres_env(raiz / '.env')), encoding='utf-8')
        cifrado = cifrar_env(raiz / '.env', destino / 'env.age', os.environ.get('AGE_RECIPIENTE', ''))

        digest = hashlib.file_digest(archivo.open('rb'), 'sha256').hexdigest()
        (destino / 'SHA256SUMS').write_text(f'{digest}  data.tar.gz\n')
        manifiesto = {
            'software': 'Uptime Kuma',
            'version': VERSION,
            'database': 'sqlite',
            'sha256': digest,
            'status': 'completed',
            'env_vars': len(nombres_env(raiz / '.env')),
            'env_cifrado': bool(cifrado),
        }
        (destino / 'manifest.json').write_text(json.dumps(manifiesto, indent=2))
    finally:
        dc('start', 'kuma')
    return destino


def main(argv=None):
    parser = argparse.ArgumentParser(description='Respaldo de Uptime Kuma.')
    parser.add_argument('--destino', default=None,
                        help='directorio donde se crea el respaldo (por defecto, ./backups)')
    args = parser.parse_args(argv)

    if args.destino:
        destino = Path(args.destino) / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    else:
        destino = RAIZ / 'backups' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')

    carpeta = construir_respaldo(destino)
    print(f'Respaldo completo: {carpeta}. '
          'Cifrar y copiar fuera del servidor; contiene datos del cliente.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
