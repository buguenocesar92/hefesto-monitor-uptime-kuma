#!/usr/bin/env python3
"""Backup coherente de todo /app/data; requiere Docker Compose y tiempo de parada."""
import datetime,hashlib,json,os,subprocess,sys,tarfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
os.chdir(root);os.umask(0o077)
if not (root/'.env').is_file():raise SystemExit('Falta .env')
def dc(*args,**kwargs):return subprocess.run(['docker','compose',*args],check=True,**kwargs)
# No arrancar accidentalmente una instancia que ya estaba detenida.
active=dc('ps','--status','running','-q','kuma',capture_output=True,text=True).stdout.strip()
if not active:raise SystemExit('kuma no esta en ejecucion en este contexto Compose. Verifica proyecto/recurso.')
folder=root/'backups'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
folder.mkdir(parents=True,exist_ok=False)
archive=folder/'data.tar.gz'
try:
    dc('stop','kuma')
    with archive.open('wb') as out:
        dc('run','--rm','--no-deps','-T','--user','0:0','--entrypoint','tar','kuma','-czf','-','-C','/app/data','.',stdout=out)
    with tarfile.open(archive,'r:gz') as t:
        if not any(m.name.endswith('kuma.db') for m in t):raise RuntimeError('No se encontro kuma.db; revisar tipo DB e instalacion')
    for filename in ['compose.yaml','.env']:(folder/filename).write_bytes((root/filename).read_bytes())
    digest=hashlib.file_digest(archive.open('rb'),'sha256').hexdigest()
    (folder/'SHA256SUMS').write_text(f'{digest}  data.tar.gz\n')
    (folder/'manifest.json').write_text(json.dumps({'software':'Uptime Kuma','version':'2.5.6','database':'sqlite','sha256':digest,'status':'completed'},indent=2))
finally:
    dc('start','kuma')
print(f'Respaldo completo: {folder}. Cifrar y copiar fuera del servidor; contiene secretos.')
