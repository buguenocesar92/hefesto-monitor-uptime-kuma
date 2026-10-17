# Despliegue y primer acceso
## Preparar
DNS monitor.cliente.cl al VPS, TLS válido y Docker Compose v2. Registrar nombres de proyecto y volumen generados. No subir .env ni respaldos al repositorio. No hay que obtener API keys para iniciar Uptime Kuma.

## Bootstrap privado
Usar comandos de README en el mismo VPS de destino. El override publica solo127.0.0.1:3001. Conectar por túnel SSH, seleccionar SQLite si lo solicita y crear la cuenta administradora, contraseña única y2FA. Probar cierre y reingreso antes de exponer HTTPS. El nombre del volumen explícito permite conservar los datos al mover de Compose manual a Coolify.

## Recurso de Coolify
1. Después de detener bootstrap, crear recurso Docker Compose con compose.yaml en un repositorio privado.
2. Configurar COMPOSE_PROJECT_NAME y DATA_VOLUME con los valores del bootstrap; DATA_VOLUME debe coincidir exactamente. Revisar la configuración renderizada en Coolify y comprobar que no renombre el volumen.
3. Asignar https://monitor.cliente.cl al servicio kuma, puerto3001. Solo entonces desplegar.
4. El proxy debe soportar WebSocket y preservar Host y protocolo HTTPS. No desactivar comprobación de origen para resolver una mala configuración del proxy.
5. Verificar que muestra login, NO la pantalla para crear el primer usuario. Si aparece setup, retirar el dominio y corregir volumen antes de continuar.
6. Confirmar salud, login, persistencia, certificados y página de estado seleccionada.

La base no requiere Nginx adicional: Coolify hace de proxy. La administración debe permanecer autenticada. Las páginas de estado se crean y publican de forma intencional; no añadir secretos, URLs privadas o nombres internos a páginas públicas.

## Alcance de red
No hay socket Docker montado ni puerto de SQLite. HTTP/TCP/DNS necesitan salida a sus destinos. Para servicios privados, usar una VPN o red explícita aprobada; no abrir la base de datos del cliente a Internet para monitorearla. No asignar privilegios adicionales salvo requisito real revisado.

## Secretos
Cuenta y2FA se crean en interfaz; credenciales de SMTP/webhooks/push se configuran allí y pueden persistir en el volumen. Son secretos tanto el respaldo como los datos del servidor. El .env de este paquete contiene nombres de proyecto/volumen, no contraseñas ficticias.
