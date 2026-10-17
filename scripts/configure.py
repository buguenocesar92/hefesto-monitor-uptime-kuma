#!/usr/bin/env python3
import os,re,sys
from pathlib import Path
if len(sys.argv)!=2 or not re.fullmatch(r'[a-z][a-z0-9-]{2,39}',sys.argv[1]):
    raise SystemExit('Uso: python3 scripts/configure.py cliente-demo (3-40 letras minusculas/digitos/guiones)')
root=Path(__file__).resolve().parents[1]
slug=sys.argv[1]
try: fd=os.open(root/'.env',os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
except FileExistsError: raise SystemExit('.env ya existe; no se modifico.')
with os.fdopen(fd,'w') as f:
    f.write(f'COMPOSE_PROJECT_NAME=hefesto-monitor-{slug}\nDATA_VOLUME=hefesto-monitor-{slug}-data\n')
print('.env creado. Conserva estos nombres para respaldar y trasladar los mismos datos.')
