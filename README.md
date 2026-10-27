# Hefesto Monitor · Uptime Kuma 2.5.6
Paquete para implementar monitoreo de disponibilidad como servicio de Hefesto: sitios web, endpoints de salud, puertos TCP, certificados HTTPS, notificaciones y páginas de estado nativas.

## Stack elegido
Uptime Kuma oficial 2.5.6-slim + SQLite en volumen Docker local + proxy HTTPS de Coolify. La versión slim no incluye Chromium ni MariaDB embebida. Este paquete no implementa monitores de navegador ni monitoreo de contenedores mediante el socket de Docker.

SQLite es suficiente como punto de partida y permite respaldar la instancia completa. No necesita Supabase; no se ha creado un adaptador PostgreSQL. Una instancia separada por cliente para entrega independiente, o una instancia operada exclusivamente por Hefesto con páginas de estado seleccionadas. No ofrecer permisos multiempresa que esta configuración no implementa.

## Estado del entregable
Configuración y scripts revisados estáticamente. No desplegado ni ejecutado con Docker en este entorno. Administrador, monitores y destinos de alerta deben configurarse durante puesta en marcha. No hay credenciales, datos reales ni notificaciones enviadas.

## Inicio
1. Extraer y ejecutar `python3 scripts/configure.py cliente-demo` (Python3.11+).
2. En el VPS: `docker compose -f compose.yaml -f compose.bootstrap.yaml up -d`.
3. Abrir túnel SSH desde tu computador: `ssh -L 3001:127.0.0.1:3001 usuario@IP_DEL_VPS`.
4. Visitar http://127.0.0.1:3001 y elegir SQLite si aparece selector. Crear administrador y activar 2FA. Guardar recuperación en gestor seguro.
5. Detener bootstrap con `docker compose -f compose.yaml -f compose.bootstrap.yaml down` SIN `-v`.
6. Seguir docs/COOLIFY.md para usar el MISMO volumen y publicar HTTPS.
7. Crear monitores a partir del catálogo y ejecutar el acta de aceptación.

No publicar una instalación vacía antes de crear su administrador. No ejecutar dos instancias sobre el mismo volumen. En Coolify, la configuración base no publica puertos al host.

## Despliegue en Coolify (MVP Hefesto)

`compose.yaml` está pensado para Coolify: build pack Docker Compose, Traefik
como proxy HTTPS, y nada que se salte el proxy ni dé poder sobre el host
(sin `ports:`, `container_name`, `privileged`, `cap_add`, `devices`,
`network_mode: host`, `pid/ipc: host`, `security_opt: unconfined`, ni
binds fuera del repo o a `docker.sock`). Los nombres de proyecto y volumen
son parametrizados con variables de entorno.

Variables que Coolify debe inyectar en el recurso:

- `COMPOSE_PROJECT_NAME` — definirlo a mano en el recurso con el mismo valor
  usado en el bootstrap (lo exige `name:` del compose); Coolify no lo rellena.
- `DATA_VOLUME` — nombre del volumen Docker con los datos de Uptime Kuma
  (SQLite, configuración, adjuntos). **Debe coincidir** con el volumen
  creado por el bootstrap (`hefesto-monitor-<cliente>-data`).

Pasos operativos antes de publicar el dominio (detalle en `docs/COOLIFY.md`):

- Crear el administrador y la 2FA por túnel a `127.0.0.1:3001` **antes**
  de asignar el dominio en Coolify; un primer visitante sobre dominio
  público crearía el admin sobre HTTPS, lo que no se puede deshacer sin
  reinstalar.
- Después del despliegue, verificar que la URL muestra la pantalla de
  **login**; si aparece la pantalla de setup del primer usuario, el
  volumen no coincide con el del bootstrap y hay que corregir
  `DATA_VOLUME` antes de continuar.
- El proxy debe soportar WebSocket: Uptime Kuma lo usa para push en vivo
  del panel y de las páginas de estado.

Antes de desplegar, conviene correr el verificador estático:

```
bash scripts/coolify-check.sh
```

Falla si el compose rompe el contrato de Coolify; devuelve `exit=0` cuando
está conforme.

## Menor privilegio

El servicio web **no corre como root**. `compose.yaml` lo declara explícito:

- `user: "1000:1000"`: usuario sin privilegios.
- `security_opt: [no-new-privileges:true]`: el proceso no puede ganar
  privilegios que no tenía.
- `cap_drop: [ALL]`: sin capacidades de Linux.

**`cap_add` no es la respuesta.** Agregar `cap_add` para resolver un problema
de privilegios rompe el contrato de Coolify: un contenedor con capacidades
extra puede saltarse el aislamiento. Cuando hace falta resolver algo que
parece pedir una capacidad, la alternativa es un usuario que no la necesite: el
servicio `permisos` (un solo disparo, con la misma imagen fijada por digest)
deja el volumen `data` con el dueño de ese usuario, y el servicio web arranca
después con `depends_on: service_completed_successfully`.

`scripts/coolify-check.sh` verifica las tres reglas: un servicio que expone un
puerto que no corra como root, o que no traiga `no-new-privileges` o
`cap_drop: ALL`, hace fallar el verificador.

## Respaldo y restauración

`scripts/backup.py` produce, en `backups/<timestamp>/`:

| Archivo | Qué es |
|---|---|
| `data.tar.gz` | dump de `/app/data` (verificado: contiene `kuma.db`) |
| `SHA256SUMS` | sha256 de `data.tar.gz` |
| `manifest.json` | `software`, `version`, `database`, `sha256`, `status` |
| `env.vars` | **solo los nombres** de variable del `.env`, nunca los valores |
| `env.age` | el `.env` cifrado con `age`, si hay `AGE_RECIPIENTE` configurado |

**El `.env` no se copia en claro.** Si no hay receptor `age` configurado, el
respaldo sale sin él y el manifiesto lo dice; no hay modo degradado a texto
plano. Con `AGE_RECIPIENTE` definido pero sin `age` instalado, el respaldo
falla en vez de dejar el `.env` a la vista.

`scripts/restore.py` valida manifiesto, checksum y rutas del tar, exige que el
volumen destino esté vacío, no arranca el servicio y deja un rastro de
auditoría en `logs/restore.log` (origen, sha256 verificado, destino, resultado).

El contrato completo, que es normativo para todo el ecosistema Hefesto, está en
`docs/CONTRATO-RESPALDO.md`. La política de datos personales (Ley 21.719) está
en `docs/POLITICA-DATOS-PERSONALES.md`.

## Pruebas y CI

```bash
bats tests/                     # 19 pruebas
bats tests/backup_restore.bats  # ciclo backup -> restore con datos sintéticos
bats tests/compose.bats         # contrato del compose (menor privilegio)
bats tests/lineas.bats          # finales de linea LF y sintaxis
```

Las pruebas del ciclo usan datos sintéticos, un `.env` temporal y un stub de
`docker`: **no levantan ningún contenedor ni tocan ningún volumen real**.

La CI (`.github/workflows/ci.yml`) corre en cada push y pull request:
`docker compose config` con el `.env` de ejemplo, `py_compile`, `shellcheck`,
la suite `bats` y `gitleaks` sobre el historial.

## Contenido
Compose de producción y bootstrap, configuración por cliente, respaldo y restauración a volumen vacío, guías de operación y transferencia, catálogo CSV de monitores, plantillas de incidentes y reporte mensual.

Este ZIP contiene el paquete de instalación; Docker descarga la aplicación oficial. No contiene binarios, historial ni monitores ya creados. Las plantillas no son importaciones automáticas ni un clon del panel nativo.

## Recursos
Punto de partida orientativo para pocos monitores: 1vCPU, 1GB RAM y10GB SSD local, ajustando después de medir carga/retención. No usar NFS para SQLite. Configurar retención de historial y vigilar disco. Si se monitorea el mismo VPS que aloja Kuma, una caída total impide alertar: usar una ubicación independiente para supervisión externa.

## Licencia
Uptime Kuma mantiene su licencia MIT y atribuciones oficiales. Hefesto cobra implementación, alojamiento, operación y soporte. Este paquete no convierte el software upstream en desarrollo propio ni garantiza disponibilidad por sí solo.
