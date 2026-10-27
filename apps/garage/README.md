# Garage — hogar y autos

App nativa SwiftUI para iPhone (iOS 17+) con dashboard del mes, finanzas familiares y autos. Los autos, servicios, cargas y lugares de gastos se sincronizan en una zona familiar de CloudKit. El registro y presupuesto de gastos viven en la planilla de Google Sheets existente.

## Configuración de Google Sheets

1. Proyecto Google Cloud: `garage-familiar-schoren-2026`, con **Google Sheets API** habilitada.
2. La pantalla de consentimiento OAuth debe incluir el alcance `https://www.googleapis.com/auth/spreadsheets`. Agregá las cuentas familiares como usuarios de prueba mientras la app esté en modo de prueba. En ese modo Google hace expirar la autorización y el refresh token a los siete días; para sesiones persistentes, completá la publicación OAuth según las opciones de tu cuenta de Google.
3. El cliente OAuth de tipo iOS para Bundle ID `com.schoren.garage` está en `App/GoogleConfig.xcconfig`. Garage Prueba (`com.schoren.garage.preview`) tiene un cliente iOS distinto y se configura al compilar la instalación de prueba. Los IDs de cliente son públicos y no requieren secretos en Infisical.
4. Compartí [la planilla familiar](https://docs.google.com/spreadsheets/d/1U0yGuLsn2UfWi309xsY7gW-_IJCd5nh1nJ1NQ6Ip654/edit) con permiso de edición a cada cuenta que vaya a iniciar sesión en Garage.
5. Si rotás el cliente principal, ejecutá `./apps/garage/scripts/configure-google-oauth.sh '<ID-del-cliente-iOS>'` desde la raíz del repositorio y recompilá. El script configura el esquema de retorno de OAuth en `App/GoogleConfig.xcconfig`.

Garage usa el acceso OAuth directamente desde cada iPhone; no hay servidor intermedio. El ID de cliente puede versionarse, pero cada integrante debe autorizar Google Sheets en su teléfono. Las escrituras fallidas quedan pendientes localmente con un ID estable para evitar duplicados al reintentar. La app lee las filas B:G de `Registro de Gastos`, los presupuestos de `Control Mensual` y los ingresos de `Presupuesto y Balance`; la columna G de gastos contiene el ID de Garage y está oculta. Las fórmulas actuales llegan a la fila 1000, por lo que se debe extender esa plantilla antes de superar ese límite.

## Gastos por voz con ChatGPT

La pantalla de gastos tiene un botón **Hablar** que abre una pantalla de escucha. Al detectar silencio, Garage termina el dictado, espera la interpretación y vuelve al formulario con los campos completos para revisarlos antes de guardar. Apple Speech convierte voz a texto **en el iPhone** si el dispositivo admite el reconocimiento local en español. Garage envía solo el texto transcrito a OpenAI y recibe un JSON con importe, categoría, pagador, detalle y fecha. La clasificación usa el significado de todas las categorías del presupuesto, sin reglas para frases puntuales. Al decirle a Siri **Registra en Garage**, Siri pregunta qué gasto querés registrar y Garage abre el formulario después de interpretar la respuesta. En la versión de prueba, el nombre de la app para Siri es **Garage Prueba**. Siri no permite pasar una descripción libre del gasto dentro de la misma frase que activa un App Shortcut.

Cada integrante conecta o desconecta su cuenta de ChatGPT desde el menú **⋯** de Inicio, junto a los controles de Google. Garage usa el flujo de Sign in with ChatGPT para proyectos locales: OAuth con PKCE y retorno a un servidor temporal en `127.0.0.1` dentro del iPhone. El token se verifica y se guarda en el llavero local del dispositivo; no se agrega a Infisical ni al repositorio. La app renueva el token, consulta los modelos disponibles de esa cuenta y llama a Responses API con `store: false` y `stream: true`. Este flujo consume el plan y sus límites de uso de cada cuenta. Requiere conexión a Internet y una cuenta elegible.

## Funciones

- Inicio muestra un dashboard gráfico del mes actual con ingresos, gastos, balance, comparación por categoría y últimos movimientos. La pestaña «Autos» conserva las cargas y el plan del auto seleccionado; «Mis autos» concentra agregar, seleccionar y eliminar autos.
- En «Ver todos» los gastos, deslizar hacia la derecha permite editar fecha, categoría, pagador, detalle e importe; deslizar hacia la izquierda permite eliminarlos con confirmación. Los cambios se escriben en la planilla y actualizan o quitan el lugar asociado en iCloud. Los registros de autos vinculados se conservan.
- Autos con marca, modelo, versión y año elegidos del catálogo de [ArgAutos](https://argautos.com/docs/api), más patente y kilometraje. Las versiones se agrupan por nombre ignorando el año final, para todas las marcas y modelos. El selector de años reúne los años explícitos de esas versiones y las valuaciones de la versión base; si la consulta de valuaciones falla, se puede ingresar solo el año. Las consultas se guardan en caché durante siete días. La patente se guarda en mayúsculas y el kilometraje comienza vacío y es obligatorio para guardar. Los cambios se guardan en el iPhone aunque iCloud no esté disponible y quedan pendientes de sincronización.
- Planes con detalle libre para especificar aceite, viscosidad, marca, filtro, repuestos o instrucciones; frecuencia en meses, kilómetros o ambos.
- Planes base sugeridos para Volkswagen Taos TSI 2021–2026 (service 15.000 km/12 meses y líquido de frenos 24 meses) y Toyota Corolla 2020–2026 (service 10.000 km/12 meses). Garage los ofrece al guardar un auto compatible o desde su ficha y muestra la fuente oficial. Se pueden agregar tareas sin conocer la última realización: quedan pendientes de revisión, sin una fecha de vencimiento inventada. Cuando se conoce, se carga fecha y kilometraje para calcular el próximo aviso. Los planes importados conservan el enlace a la fuente y no se duplican.
- Recomendaciones por tarea, seleccionadas por defecto y desactivables: presión, rotación y desgaste de cubiertas; escobillas; frenos; aceite de caja; filtros de motor y habitáculo; refrigeración; correas; batería; luces y lavaparabrisas; dirección, suspensión y climatización. Cada regla distingue inspección de reemplazo y enlaza su fuente. El aceite de caja, las cubiertas y otras piezas sujetas a condición se revisan periódicamente, pero no se marcan para reemplazo automático.
- Estado próximo/vencido cuando se alcanza cualquiera de las dos condiciones.
- En «Mis autos», deslizar una fila permite eliminar un auto propio junto con sus services, o quitar de la cuenta un auto compartido por otra persona. La eliminación se guarda localmente y se sincroniza con iCloud al recuperar conexión.
- Registro de cada service con fecha, kilometraje, notas, costo y pagador. Actualiza el próximo vencimiento y crea el gasto en la planilla.
- Registro de cargas de nafta por auto con estación editable, fecha, kilómetros, litros, precio por litro y pagador; el total en pesos se calcula en el formulario y se registra en la planilla. La carga se conserva localmente y se sincroniza por iCloud con el auto. Se puede buscar la estación cercana con MapKit o elegir YPF, Shell, Axion, Puma u otro nombre a mano.
- Avisos opcionales de posibles cargas: con permiso de ubicación «Siempre», iOS informa visitas y Garage busca una estación de servicio cercana. Solo sugiere registrar una carga cuando la visita informada dura al menos cinco minutos; el aviso puede llegar más tarde porque iOS entrega las visitas de forma aproximada. No se registra una carga automáticamente ni se usa seguimiento GPS continuo.
- Notificaciones locales por fecha, al acercarse el vencimiento, y por kilometraje al ingresar una nueva lectura. Cada iPhone calcula sus propias notificaciones.
- Invitar a colaborar en el espacio familiar completo vía iCloud: la zona incluye todos los autos y lugares guardados para sugerir gastos. Los gastos y presupuestos de la planilla requieren además acceso de Google a ese archivo. Al abrir la nueva versión, Garage copia los registros de las zonas antiguas por auto a la zona familiar con IDs estables; conserva las zonas originales como respaldo.
- La pantalla «Acceso familiar» consulta iCloud para mostrar colaboradores y si la invitación está pendiente o aceptada. El propietario puede quitar el acceso de una persona; el cambio se guarda en CloudKit. Los nombres pueden no estar disponibles si iCloud no comparte la identidad del participante.
- Cada integrante elige una vez su nombre de la columna «Pagado por» en «Mi nombre en el presupuesto». Garage guarda esa elección en el dispositivo y la sincroniza con la zona familiar de CloudKit cuando está disponible. Ese nombre aparece por defecto en gastos, nafta y services. Si aún no eligió su nombre, debe seleccionar un pagador antes de guardar; «Común» sigue disponible como elección manual. Garage ofrece como pagadores a integrantes activos más «Común». Los nombres disponibles deben existir antes en la lista de pagadores de la planilla (`FamilyBudget.payers`).

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

Para compartir el espacio familiar, primero debe terminar de sincronizarse. El odómetro no se lee del vehículo: el usuario debe actualizarlo; una alerta por kilómetros no puede dispararse sin una lectura nueva. Los cambios de otro participante se leen al abrir la app o al deslizar para actualizar. Las plantillas son planes base, no contienen la marca o viscosidad de aceite ni todas las tareas específicas de cada versión; se debe revisar el manual del vehículo. Esta versión no incluye edición o borrado de planes, fotos de facturas ni avisos remotos de cambios. El entorno CloudKit real, la migración y el enlace de invitación requieren validación en dos dispositivos firmados; el simulador sólo valida compilación y UI.
