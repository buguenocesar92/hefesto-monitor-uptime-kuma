#!/usr/bin/env python3
"""Restaura solo en volumen vacio. No arranca el servidor ni envia alertas."""
import hashlib,json,os,subprocess,sys,tarfile
from pathlib import Path,PurePosixPath
if len(sys.argv)!=2:raise SystemExit('Uso: python3 scripts/restore.py /ruta/respaldo')
backup=Path(sys.argv[1]).resolve();root=Path(__file__).resolve().parents[1]
os.chdir(root)
if not (root/'.env').is_file():raise SystemExit('Configurar primero el proyecto de destino con scripts/configure.py')
a=backup/'data.tar.gz';m=json.loads((backup/'manifest.json').read_text())
with a.open('rb') as f: digest=hashlib.file_digest(f,'sha256').hexdigest()
if m.get('status')!='completed' or m.get('version')!='2.5.6' or digest!=m.get('sha256'):
    raise SystemExit('Version/manifest/checksum no valido')
with tarfile.open(a,'r:gz') as t:
    for x in t:
        path=PurePosixPath(x.name)
        if path.is_absolute() or '..' in path.parts or not (x.isfile() or x.isdir()):
            raise SystemExit('Archivo con rutas o tipos no permitidos')
def dc(*args,**kw):return subprocess.run(['docker','compose',*args],check=True,**kw)
if dc('ps','--status','running','-q','kuma',capture_output=True,text=True).stdout.strip():
    raise SystemExit('Destino en ejecucion. Usar instancia nueva y detenerla primero.')
# Nunca vaciar ni sobrescribir datos existentes. Detectar tambien archivos ocultos.
probe=dc('run','--rm','--no-deps','-T','--user','0:0','--entrypoint','find','kuma','/app/data','-mindepth','1','-maxdepth','1',capture_output=True,text=True)
if probe.stdout.strip():raise SystemExit('Volumen destino no vacio: restauracion cancelada.')
with a.open('rb') as source:
    dc('run','--rm','--no-deps','-T','--user','0:0','--entrypoint','tar','kuma','-xzf','-','-C','/app/data',stdin=source)
print('Datos restaurados. Servicio NO iniciado. Revisa notificaciones y aislamiento antes de arrancar.')
