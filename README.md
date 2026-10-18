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

## Contenido
Compose de producción y bootstrap, configuración por cliente, respaldo y restauración a volumen vacío, guías de operación y transferencia, catálogo CSV de monitores, plantillas de incidentes y reporte mensual.

Este ZIP contiene el paquete de instalación; Docker descarga la aplicación oficial. No contiene binarios, historial ni monitores ya creados. Las plantillas no son importaciones automáticas ni un clon del panel nativo.

## Recursos
Punto de partida orientativo para pocos monitores: 1vCPU, 1GB RAM y10GB SSD local, ajustando después de medir carga/retención. No usar NFS para SQLite. Configurar retención de historial y vigilar disco. Si se monitorea el mismo VPS que aloja Kuma, una caída total impide alertar: usar una ubicación independiente para supervisión externa.

## Licencia
Uptime Kuma mantiene su licencia MIT y atribuciones oficiales. Hefesto cobra implementación, alojamiento, operación y soporte. Este paquete no convierte el software upstream en desarrollo propio ni garantiza disponibilidad por sí solo.
