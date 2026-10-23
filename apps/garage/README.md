# Garage — services del auto

App nativa SwiftUI para iPhone (iOS 17+) que guarda autos, planes de servicio e historial en CloudKit. Cada auto tiene una zona privada separada para compartir sólo ese auto con otra persona mediante la interfaz de iCloud, sin cuentas ni servidor propios.

## Funciones

- Inicio muestra directamente las cargas y el plan del auto seleccionado. El selector superior permite cambiar de auto y recuerda la elección en este iPhone; al principio propone el auto con más cargas registradas. La pestaña «Mis autos» concentra agregar, seleccionar y eliminar autos.
- Autos con marca, modelo, versión y año elegidos del catálogo de [ArgAutos](https://argautos.com/docs/api), más patente y kilometraje. Las versiones se agrupan por nombre ignorando el año final, para todas las marcas y modelos. El selector de años reúne los años explícitos de esas versiones y las valuaciones de la versión base; si la consulta de valuaciones falla, se puede ingresar solo el año. Las consultas se guardan en caché durante siete días. La patente se guarda en mayúsculas y el kilometraje comienza vacío y es obligatorio para guardar. Los cambios se guardan en el iPhone aunque iCloud no esté disponible y quedan pendientes de sincronización.
- Planes con detalle libre para especificar aceite, viscosidad, marca, filtro, repuestos o instrucciones; frecuencia en meses, kilómetros o ambos.
- Planes base sugeridos para Volkswagen Taos TSI 2021–2026 (service 15.000 km/12 meses y líquido de frenos 24 meses) y Toyota Corolla 2020–2026 (service 10.000 km/12 meses). Garage los ofrece al guardar un auto compatible o desde su ficha y muestra la fuente oficial. Se pueden agregar tareas sin conocer la última realización: quedan pendientes de revisión, sin una fecha de vencimiento inventada. Cuando se conoce, se carga fecha y kilometraje para calcular el próximo aviso. Los planes importados conservan el enlace a la fuente y no se duplican.
- Recomendaciones por tarea, seleccionadas por defecto y desactivables: presión, rotación y desgaste de cubiertas; escobillas; frenos; aceite de caja; filtros de motor y habitáculo; refrigeración; correas; batería; luces y lavaparabrisas; dirección, suspensión y climatización. Cada regla distingue inspección de reemplazo y enlaza su fuente. El aceite de caja, las cubiertas y otras piezas sujetas a condición se revisan periódicamente, pero no se marcan para reemplazo automático.
- Estado próximo/vencido cuando se alcanza cualquiera de las dos condiciones.
- En «Mis autos», deslizar una fila permite eliminar un auto propio junto con sus services, o quitar de la cuenta un auto compartido por otra persona. La eliminación se guarda localmente y se sincroniza con iCloud al recuperar conexión.
- Registro de cada service con fecha, kilometraje y notas. Actualiza el próximo vencimiento.
- Registro de cargas de nafta por auto con estación editable, fecha, kilómetros, litros y precio por litro; el total en pesos se calcula en el formulario. La carga se conserva localmente y se sincroniza por iCloud con el auto. Se puede buscar la estación cercana con MapKit o elegir YPF, Shell, Axion, Puma u otro nombre a mano.
- Avisos opcionales de posibles cargas: con permiso de ubicación «Siempre», iOS informa visitas y Garage busca una estación de servicio cercana. Solo sugiere registrar una carga cuando la visita informada dura al menos cinco minutos; el aviso puede llegar más tarde porque iOS entrega las visitas de forma aproximada. No se registra una carga automáticamente ni se usa seguimiento GPS continuo.
- Notificaciones locales por fecha, al acercarse el vencimiento, y por kilometraje al ingresar una nueva lectura. Cada iPhone calcula sus propias notificaciones.
- Invitar a colaborar en un auto vía iCloud: solo las personas invitadas pueden acceder y pueden editar el auto, sus cargas y servicios. Cada auto usa una zona CloudKit propia; los cambios de los participantes se leen al abrir o actualizar la app.
- La pantalla «Acceso» consulta iCloud para mostrar colaboradores y si la invitación está pendiente o aceptada. El propietario puede quitar el acceso de una persona; el cambio se guarda en CloudKit. Los nombres pueden no estar disponibles si iCloud no comparte la identidad del participante.

## Abrir y compilar

Desde la raíz:

```sh
./scripts/workspace.sh open garage
./scripts/workspace.sh build garage
```

El script de build firma el simulador con el equipo por defecto `3SRDN9365G` (se puede reemplazar con `DEVELOPMENT_TEAM=...`). CloudKit y las notificaciones se deben probar además en iPhone firmado con un Apple Developer Team. En Xcode, asignar el equipo a `Garage`, habilitar **iCloud > CloudKit**, asociar `iCloud.com.schoren.garage` (o cambiar identificadores para el equipo propio), y activar **Background Modes > Remote notifications** si se agregan suscripciones de cambios. El contenedor debe existir en CloudKit Dashboard y el esquema debe desplegarse a producción antes de distribuir la app. Ambos participantes necesitan iCloud activo.

## TestFlight

El workflow manual **Garage TestFlight** compila la configuración Release, sube el IPA con Fastlane, espera el procesamiento de TestFlight y selecciona el build en la versión editable de App Store Connect. No ejecuta pruebas. `rebuild` conserva la versión actual y usa un número de build nuevo; `major` y `minor` incrementan el componente indicado y reinician los siguientes a cero. La primera ejecución con `rebuild` usa `1.0.0`. Después de una subida exitosa, el workflow guarda un tag `garage-vX.Y.Z` para calcular la siguiente versión.

La configuración Release usa CloudKit Production. Antes del primer upload, el esquema del contenedor `iCloud.com.schoren.garage` debe estar desplegado a producción en CloudKit Console.

Las credenciales **exclusivas de Garage** se guardan en Infisical, proyecto `CLI General`, entorno `prod`, carpeta `/garage-ios-appstore`. GitHub Actions guarda solamente `GARAGE_INFISICAL_TOKEN`, un token de Infisical con acceso de lectura a esa carpeta. El workflow instala Infisical CLI y carga las credenciales en cada ejecución.

| Secreto de Infisical | Contenido |
| --- | --- |
| `GARAGE_ASC_KEY_ID` | ID de la API key de App Store Connect creada para Garage. |
| `GARAGE_ASC_ISSUER_ID` | Issuer ID de esa API key. |
| `GARAGE_ASC_KEY_P8_BASE64` | Archivo `.p8` de esa API key codificado en base64, sin saltos de línea. |
| `GARAGE_DISTRIBUTION_CERTIFICATE_P12_BASE64` | Certificado Apple Distribution y clave privada exclusivos, exportados como `.p12` y codificados en base64. |
| `GARAGE_DISTRIBUTION_CERTIFICATE_PASSWORD` | Contraseña del `.p12`. |
| `GARAGE_APPSTORE_PROFILE_BASE64` | Perfil iOS App Store para `com.schoren.garage`, asociado a ese certificado, codificado en base64. |
| `GARAGE_KEYCHAIN_PASSWORD` | Contraseña aleatoria para el llavero temporal del runner. |

El registro `Garage` en App Store Connect debe usar `com.schoren.garage`. El upload deja el build procesado en TestFlight y seleccionado en la versión de App Store; completar la ficha y enviarlo a Apple para revisión pública requiere los datos y capturas de la ficha.

## Alcances actuales

Para compartir un auto, primero debe terminar de sincronizarse. El odómetro no se lee del vehículo: el usuario debe actualizarlo; una alerta por kilómetros no puede dispararse sin una lectura nueva. Los cambios de otro participante se leen al abrir la app o al deslizar para actualizar. Las plantillas son planes base, no contienen la marca o viscosidad de aceite ni todas las tareas específicas de cada versión; se debe revisar el manual del vehículo. Esta primera versión no incluye edición o borrado de planes, fotos de facturas ni avisos remotos de cambios. El entorno CloudKit real y el enlace de invitación requieren validación en dos dispositivos firmados; el simulador sólo valida compilación y UI.
