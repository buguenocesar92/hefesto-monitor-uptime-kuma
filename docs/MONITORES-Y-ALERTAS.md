# Configuración funcional
El CSV examples/catalogo-monitores.csv es una ficha de planificación; no importarlo como si fuera un formato oficial. Crear monitores desde la interfaz nativa. Comenzar con un conjunto pequeño y ajustar umbrales con datos reales.

## Perfil recomendado de inicio
- Sitio público: HTTP(S), URL principal autorizada, intervalo60s, timeout20s y2 reintentos si los controles nativos lo permiten. Revisar que un302 a una página de error no aparezca como éxito.
- API de aplicación: HTTP(S) con una ruta /health implementada por esa aplicación y respuesta esperada. No asumir que Odoo, Moodle o Nextcloud tienen la misma ruta.
- TCP: host/puerto autorizado; solo confirma conexión, no disponibilidad funcional.
- Certificados: activar verificación TLS y avisos de vencimiento en los monitores HTTPS compatibles. Una alerta de vencimiento no renueva certificados.
- DNS: consultar registro esperado mediante monitor DNS, sin confundir respuesta DNS con funcionamiento del sitio.
- Copias de respaldo: monitor Push con intervalo acorde al trabajo; enviar éxito solo al terminar y verificar el respaldo. Guardar URL tokenizada como secreto. Este paquete no conecta ese push automáticamente.

Usar nombres cliente-entorno-servicio. Separar producción y pruebas mediante etiquetas. Nunca presentar un200 como garantía de que pagos o login funcionan. Los flujos de compra requieren pruebas sintéticas específicas, fuera del alcance de esta edición slim.

## Alertas
Elegir SMTP, Telegram u otro proveedor disponible en la interfaz. Obtener credenciales de su dueño, configurar destino autorizado y enviar una prueba manual. Luego asociar la notificación a cada monitor; crear el proveedor no garantiza que esté asociado. Telegram requiere bot/token/chatID propios; SMTP requiere servidor y remitente autorizado. No hay envío automático desde este ZIP.

Probar caída y recuperación en un endpoint de pruebas propio, sin apagar servicios de clientes. Confirmar llegada, tiempos, destinatarios y deduplicación. Ajustar reintentos para evitar alertas por fallos breves. El tiempo de detección depende de intervalo, timeout, reintentos y proveedor; no prometer detección instantánea.

## Mantenimiento
Registrar una ventana nativa antes de mantenimiento programado. Comprobar que suprime alertas según la configuración real y finaliza en el horario esperado. Revisar zona horaria del navegador y servidor. Toda alerta importante requiere responsable y canal alternativo.

## Página de estado
Crear slug y título por cliente, seleccionar solo monitores que se puedan publicar y revisar con una sesión sin login. Preparar incidentes y mantenimiento desde las opciones disponibles. Las páginas no sustituyen un sistema de tickets ni registros de auditoría completos.
