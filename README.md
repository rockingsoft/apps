# Agenda — macOS, iPhone y iPad

App nativa SwiftUI + extensiones WidgetKit, inspirada en la referencia: calendario mensual claro, año rojo, día actual azul, indicadores de color y agenda oscura agrupada por fecha.

## Abrir

Abrir `CalendarWidget.xcodeproj` en Xcode. Elegir:

- **AgendaMac**: ventana y panel en la barra de menú (macOS 14+).
- **AgendaiOS**: app universal para iPhone/iPad (iOS/iPadOS 17+).

### Instalar el widget en Mac

Compilar sin firma y abrir desde `build/mac` no registra correctamente el widget. Para instalar la app firmada con la extensión:

```sh
DEVELOPMENT_TEAM=3SRDN9365G ./scripts/install-mac.sh
open ~/Applications/Agenda.app
```

Con la app abierta, conceder los permisos si macOS vuelve a solicitarlos por el cambio de firma. Abrir el Centro de notificaciones (clic en la fecha/hora), elegir **Editar widgets**, buscar **Agenda** y agregar **Calendario y recordatorios**. También se puede agregar al escritorio. El widget es una extensión separada: la ventana de la app sirve para permisos, filtros y la agenda completa.

macOS usa el App Group `$(DEVELOPMENT_TEAM).com.schoren.calendarwidget`, que se valida mediante la firma del equipo sin necesitar registrar un grupo iOS. `AgendaAppGroup` en el Info.plist expandido conecta el mismo identificador con la app y su extensión. Ver [documentación de Apple sobre App Groups en macOS](https://developer.apple.com/documentation/xcode/accessing-app-group-containers).

Los targets incluyen sus extensiones WidgetKit, con tamaños pequeño, mediano, grande y extragrande donde el sistema lo admite. En iPhone/iPad reales, seleccionar el mismo equipo de desarrollo en la app y su extensión y configurar el App Group `group.com.schoren.calendarwidget` para ambos. Si se cambia el identificador, actualizar también `AGENDA_APP_GROUP` en la configuración del proyecto. Se necesita firma y provisioning válidos para instalar en dispositivos y validar los widgets del sistema.

Al abrir, pulsar **Permitir acceso a Calendario** y **Permitir acceso a Recordatorios**. Son permisos independientes. Si fueron denegados, habilitarlos en Ajustes del sistema → Privacidad y seguridad. La app consulta las cuentas ya configuradas en Apple Calendar y Reminders; no usa OAuth ni un servidor externo. Agregar el widget desde la galería del sistema después de abrir la app y conceder acceso.

## Funciones

- Navegación por meses, selección de día y regreso a hoy.
- Agenda de los siguientes 14 días desde la selección, eventos de varios días y de día completo.
- Colores originales de cada calendario/lista.
- Búsqueda por título o calendario dentro de los datos cargados.
- Filtro de calendarios/listas en la app y configuración independiente por widget.
- Clic derecho → Editar widget: todos los calendarios o una selección, mostrar tareas, eventos de todo el día y mes.
- El selector incluye calendarios sin eventos, a partir de las fuentes publicadas por la app.
- Botón Abrir Calendario: abre Calendario de Apple en macOS y en la fecha seleccionada en iOS.
- Unirse al próximo evento visible con enlace HTTPS reconocido de Zoom/Meet en URL, ubicación o notas (widgets medianos, grandes y extragrandes). El pequeño abre Agenda.
- Los eventos de todo el día tienen filas propias con título, color y etiqueta Todo el día. No se fusionan ni reducen a una nota al pie.
- Mes con las semanas necesarias (4, 5 o 6), sin una sexta fila vacía permanente.
- Recordatorios pendientes con fecha, vencidos y sin fecha.
- Completar recordatorios desde la app (escribe en Apple Reminders).
- Actualización al activar la app, cambiar el mes o recibir `EKEventStoreChanged`.
- La app publica la instantánea compartida junto con los permisos de cada fuente. Los widgets leen EventKit cuando tienen autorización y conservan las fuentes de la instantánea para las que la extensión no tiene acceso. La extensión nunca sobrescribe la instantánea de la app. Sin permisos muestran una indicación para conectarlos, en lugar de una agenda vacía. Solicitan actualización cada 30 minutos y preparan entradas para los horarios de inicio/fin conocidos dentro de ese período; Apple decide cuándo ejecutarlas.

El acceso a calendarios es de lectura en esta implementación. EventKit requiere el permiso denominado “acceso completo” para leerlos. Los eventos no se modifican. Completar un recordatorio sí modifica el original.

## Límites de esta versión

- No incluye el clima: requiere una integración meteorológica independiente.
- Los widgets muestran una cantidad limitada de entradas; abrir la app permite desplazarse y completar recordatorios.
- No crea/edita eventos ni crea recordatorios.
- Los datos del App Group permanecen en el dispositivo. El sistema puede mostrar datos de la última actualización si aún no ejecutó la próxima. La app vuelve a publicar la instantánea al actualizar permisos y filtros.
- Compilar sin firma verifica código y empaquetado, pero no valida permisos, provisioning, integración del App Group ni instalación del widget en un dispositivo real.

## Validación

```sh
./scripts/test.sh
xcodebuild -project CalendarWidget.xcodeproj -scheme AgendaMac -configuration Debug -derivedDataPath build/mac CODE_SIGNING_ALLOWED=NO build
xcodebuild -project CalendarWidget.xcodeproj -scheme AgendaiOS -configuration Debug -sdk iphonesimulator -derivedDataPath build/ios CODE_SIGNING_ALLOWED=NO build
```

Tests de calendario: límites de mes, año bisiesto, final exclusivo de eventos de varios días, recordatorios con/sin fecha y serialización de instantáneas. App iniciada en simuladores iPhone 17 Pro Max e iPad Pro 13; revisión visual del estado sin permisos. La lectura de eventos y recordatorios reales también fue verificada en macOS con permisos concedidos. No se completaron recordatorios reales durante las pruebas. Los widgets instalados requieren validación con firma y App Group en el dispositivo de destino.

## Proyecto

- `App/`: app y modelo observable.
- `Shared/`: tipos, fechas, acceso EventKit, caché y vistas compartidas.
- `Widget/`: proveedor de timelines y vistas WidgetKit.
- `scripts/generate-project.rb`: regeneración del proyecto (Ruby + gem `xcodeproj` 1.27). El `.xcodeproj` está incluido; no hace falta instalar Ruby para compilar.

Documentación de Apple: [acceso a EventKit](https://developer.apple.com/documentation/eventkit/accessing-the-event-store) y [WidgetKit](https://developer.apple.com/documentation/widgetkit).

## Configuración y reuniones

Cada instancia del widget guarda sus opciones mediante `WidgetConfigurationIntent` y `AppIntentConfiguration`. Desactivar Todos los calendarios permite elegir varios; una selección vacía muestra cero eventos, aunque las tareas pueden seguir visibles si están activadas. Los filtros del widget también controlan los puntos del mes y cuál es el próximo evento. Los filtros de la ventana de Agenda no modifican otras instancias del widget.

Unirse aparece solo si el próximo evento con horario tiene un enlace reconocido; no salta un evento sin enlace para ofrecer una reunión posterior. Se priorizan eventos futuros y, si no hay ninguno, uno en curso. El enlace se abre únicamente al pulsarlo. El reconocimiento exige HTTPS, un host Zoom/Meet permitido y una ruta de reunión; rechaza dominios que imitan esos nombres. Los enlaces no se visitaron durante las pruebas.

Validación adicional: selección de calendarios/tareas, meses de cinco y seis semanas, prioridad y vencimiento del próximo evento, detección de enlaces, rechazo de dominios impostores y compatibilidad con instantáneas anteriores. Diseño renderizado a 344 × 344 con una reunión de ejemplo y botón Unirse.

## Navegación dentro del widget

Tocar una celda del mes ejecuta `SelectWidgetDay` en segundo plano y muestra únicamente los eventos y las tareas con fecha de ese día, incluyendo eventos de varios días. Se puede volver con Hoy. La selección se conserva en el App Group y se separa por configuración de calendarios y opciones; dos widgets con exactamente la misma configuración comparten la fecha seleccionada. Las flechas del encabezado navegan por meses y Hoy regresa al actual. El tamaño pequeño y el modo sin mes no muestran la grilla de selección.

El botón Unirse solo se muestra si el evento del día seleccionado también es el próximo evento elegible; no aparece para reuniones pasadas. Los recordatorios sin fecha se mantienen en la app completa.

Las acciones externas pasan por el esquema local `calendarwidget://` para evitar que la URL general del widget intercepte controles internos. En macOS, Agenda funciona como agente de barra de menú y procesa el enlace en segundo plano, sin mostrar su ventana. Unirse valida nuevamente el host y abre Zoom/Meet. Cada fila de evento abre el enlace interno `ical://ekevent` con el identificador y la fecha de la ocurrencia, para mostrar directamente sus detalles en Calendario de Apple. En iOS abre Calendar en la fecha del evento. Las tareas abren Calendar en la fecha seleccionada.

La navegación mensual lee exclusivamente la instantánea del App Group. No consulta EventKit al tocar una fecha o flecha. En macOS, los controles usan el agente de barra de menú ya residente para guardar la selección y pedir la actualización; iOS conserva AppIntent. La app principal publica los eventos y el widget los reutiliza. Las grillas de cuatro, cinco y seis semanas usan alturas explícitas para mantener filas uniformes.

Los eventos del calendario Birthdays/Cumpleaños se presentan como `🎁 Nombre (Cumpleaños)` y omiten la etiqueta redundante de todo el día. En iOS, el widget mediano usa una superficie oscura continua con el mes a la izquierda, la agenda a la derecha y un contador cuando quedan eventos fuera del espacio disponible.
