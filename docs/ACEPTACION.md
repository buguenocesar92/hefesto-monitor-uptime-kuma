# Acta de aceptación pendiente
Registrar cliente, dominio, responsable, versión/digest, fecha y evidencia. Ninguna casilla se considera aprobada solo por recibir el ZIP.

- [ ] Compose valida y la imagen se descarga en la arquitectura del VPS.
- [ ] Bootstrap accesible solo por túnel; administrador y2FA creados.
- [ ] HTTPS y WebSocket funcionan; login público no permite configurar nuevo admin.
- [ ] Volumen coincide con el preparado; reinicio conserva monitores/historial.
- [ ] Monitor HTTP real y endpoint de pruebas creados con intervalos acordados.
- [ ] Fallo simulado en pruebas produce alerta al destinatario correcto.
- [ ] Recuperación produce aviso y estado correcto.
- [ ] Página de estado pública contiene solo información autorizada.
- [ ] Mantenimiento programado y zona horaria comprobados.
- [ ] Backup completo generado; restauración probada sin notificaciones duplicadas.
- [ ] Retención, monitor externo, responsables y horarios documentados.
- [ ] Credenciales y recuperación2FA entregadas por canal seguro.

Verificación durante empaquetado: sintaxis Python/shell, YAML, generador no sobrescribe .env, nombres de volumen y ZIP. No hay prueba Docker ni envío de alertas en este entorno.
