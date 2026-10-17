# Operación y traslado
## Respaldo consistente
Ejecutar `python3 scripts/backup.py` desde este paquete en el host Docker. Necesita Python3.11+, .env y el contexto Compose que realmente administra kuma. Si Coolify lo ejecuta con otro nombre/proyecto, usar su directorio y variables reales: el script se detiene si no detecta el servicio activo.

Detiene kuma, empaqueta TODO /app/data (incluye SQLite, WAL y configuración), registra SHA-256 y reinicia. Hay una interrupción de monitoreo durante la copia; programarla y no ocultarla en el informe. Revisa salida, manifest.status=completed y estado del servicio. Un respaldo fallido no debe contarse como exitoso.

Cifrar los respaldos y copiarlos fuera del VPS con una herramienta operativa de Hefesto. El script no configura almacenamiento remoto, cifrado ni cron. Retención inicial a acordar:7 diarios y4 semanales, ajustada al contrato. Evitar llenar el disco; no hay borrado automático.

## Recuperación en destino nuevo
1. Conservar una copia inmutable del respaldo y verificar checksum.
2. Descomprimir este mismo paquete en el servidor destino; ejecutar configure.py con un nuevo identificador para pruebas, o conservar nombres documentados en una migración definitiva.
3. Usar volumen local nuevo/vacío. No iniciar la app antes de restaurar.
4. Ejecutar `python3 scripts/restore.py /ruta/al/respaldo`.
5. El script verifica versión/checksum/tipos/rutas y rechaza un volumen no vacío. No elimina datos previos y no inicia el servidor.
6. Antes de arrancar una copia de pruebas, bloquear su salida externa mediante la red/firewall del entorno: restaura también tokens y proveedores de notificaciones. No permitir que la copia envíe alertas duplicadas.
7. Arrancar por bootstrap/túnel en entorno aislado. Confirmar login, monitores, datos históricos y configuración. Desactivar destinos de alerta en esa copia antes de darle salida.
8. En migración definitiva, detener origen, realizar respaldo final, restaurar destino y mover DNS. Solo una instancia debe emitir alertas. Cambiar accesos de operación y verificar recuperación.

El SHA-256 detecta corrupción accidental; no autentica un respaldo recibido de un tercero. Restaurar únicamente respaldos propios de procedencia confiable. Si falla la extracción, conservar diagnóstico y repetir en OTRO volumen vacío, no sobre datos parciales.

## Actualización
Imagen fijada a versión/digest. Leer notas oficiales, respaldar, probar nueva versión y solo después cambiar compose.yaml. Una migración de SQLite puede impedir volver atrás con solo cambiar la imagen; recuperar respaldo completo compatible. No usar actualizaciones automáticas sin validación.

## Entrega
Entregar al cliente: dominio/DNS, acceso a infraestructura, versión/digest, volumen, respaldo restaurado en pruebas, administrador y recuperación2FA por canal seguro, inventario de monitores, responsables y horarios, proveedores de alerta, retención y contrato de soporte. Quitar accesos temporales según acuerdo.
