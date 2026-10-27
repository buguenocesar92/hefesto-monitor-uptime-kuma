# Política de tratamiento de datos personales — Uptime Kuma (Hefesto Studio)

Estado: vigente desde 2026-10-20. Responsable del tratamiento: el cliente que
opera el kit. Este documento describe qué datos guarda el kit de observabilidad,
por qué, cuánto tiempo los retiene y cómo se exercise los derechos del titular
(Ley 21.719, y la Ley 19.628 en lo que corresponda a la videovigilancia de
espacios de acceso físico, no aplica aquí).

## 1. Qué datos guarda este kit

El servicio Uptime Kuma guarda, por monitor configurado:

- **Registro del monitor**: nombre, URL vigilada, tipo de chequeo (HTTP, TCP,
  DNS, push), intervalo, timeout y reintentos.
- **Historial de disponibilidad**: marca de tiempo, código de estado, duración
  del fallo y mensaje de error de cada comprobación.
- **Cuerpo de la respuesta cuando el chequeo falla**: el kit **no** lo guarda
  por defecto. Solo se guarda si el monitor está configurado explícitamente
  para bodies, y esa configuración la hace el operador, no el kit.
- **Capturas de error**: imágenes de la pantalla de error en los monitores de
  tipo navegador. La edición `slim` de Uptime Kuma **no** incluye Chromium, así
  que por defecto no hay capturas.
- **Configuración de alertas**: destino del webhook (Telegram, Slack, correo,
  ntfy) y su token. Son credenciales de un tercero y se guardan en el volumen.
- **Cuentas de administrador**: usuario, hash de contraseña y estado de 2FA.
- **Copia local de los respaldos**: `backups/<timestamp>/` incluye la
  configuración completa del servicio (monitores, alertas, usuarios) y el dump
  de la base SQLite.

## 2. Qué datos NO guarda este kit

- El `.env` **no** se copia en claro al respaldo: solo sus nombres de variable
  (`env.vars`) y, si hay un receptor `age` configurado, el `.env` cifrado
  (`env.age`). Ver `docs/CONTRATO-RESPALDO.md`, regla 5.
- El kit no guarda cuerpos de respuesta HTTP salvo que el monitor esté marcado
  como `body` de forma explícita.
- El kit no envía datos a ningún servicio de terceros por su cuenta: solo
  notifica a los destinos de alerta que el operador configura.

## 3. Base legal y deberes

- **Minimización**: el kit solo mide disponibilidad. No se instrumenta la
  sesión del usuario, ni se capturan cabeceras de autenticación, ni se registran
  cookies. La excepción es la que el operador configura de forma explícita para
  un monitor concreto, y esa excepción debe quedar justificada por escrito.
- **Finalidad**: disponibilidad de los servicios del cliente. Los datos de
  monitorización no se usan para otros fines ni se ceden a terceros.
- **Seguridad**: los respaldos se cifran en reposo (`age`), el contenedor corre
  como usuario sin privilegios, sin capacidades y con `no-new-privileges`, y el
  panel solo se expone por HTTPS detrás del proxy.
- **Auditoría**: cada operación de respaldo y de restauración deja un registro
  en `logs/restore.log` con origen, sha256 verificado, destino y resultado. Es
  registro de actividades de tratamiento: no se registran valores de secretos,
  solo nombres y hashes.

## 4. Retención

| Dato | Dónde | Retención por defecto | Quién lo borra |
|---|---|---|---|
| Historial de comprobaciones | volumen `data` (SQLite) | el que Uptime Kuma tenga configurado | el operador, desde la interfaz |
| Cuerpo de respuesta fallida | volumen `data` | solo si el monitor lo pide | el operador |
| Capturas de error | volumen `data` | no se generan en la edición slim | — |
| Respaldos en disco | `backups/<timestamp>/` | **a definir por el operador**; el kit no borra nada por su cuenta | el operador, con la política del cliente |
| Registro de auditoría | `logs/restore.log` | append-only; se trunca por política del cliente | el operador |

**El kit no borra respaldos por su cuenta.** Borrar es una decisión del
operador, porque un respaldo borrado no se recupera.

## 5. Derechos del titular (acceso, rectificación y supresión)

Cuando los datos capturados incluyan información de personas (por ejemplo, un
endpoint que devuelve identificadores de usuario o un cuerpo de respuesta con
nombres), el cliente que opera el kit debe poder atender las solicitudes de
sus titulares:

1. **Acceso**: identificar qué monitores capturan datos de personas y entregar
   la información de la SQLite (`kuma.db`) al titular que la solicite.
2. **Rectificación**: corregir o completar los datos mediante la interfaz de
   Uptime Kuma.
3. **Supresión**: eliminar los registros de la base y los respaldos que los
   contengan, y dejar constancia de la supresión en el registro de auditoría.
4. **Revocación del consentimiento**: si el tratamiento de esos datos depende
   del consentimiento del titular, dejar de capturar el cuerpo de la respuesta
   de ese monitor.

El operador es quien conoce dónde están sus datos y quién es el titular; el
kit solo garantiza que puede entregar la información, corregirla y borrarla.

## 6. Datos de los respaldos en el servidor de otro

Cuando el respaldo sale del servidor, viaja cifrado con `age` hacia el
destino que el operador designó (el repositorio de Kopia, ver
`hefesto-respaldo-kopia`). La clave privada no está en este servidor. El
servidor de destino solo ve datos cifrados.

## 7. Verificación

- `bats tests/backup_restore.bats` comprueba, con datos sintéticos, que el
  `.env` no queda en claro, que el respaldo tiene su manifiesto y que la
  restauración deja rastro de auditoría.
- `gitleaks` corre en CI sobre el repositorio y su historial.
