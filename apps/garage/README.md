# Garage — services del auto

App nativa SwiftUI para iPhone/iPad (iOS 17+) que guarda autos, planes de servicio e historial en CloudKit. Cada auto tiene una zona privada separada para compartir sólo ese auto con otra persona mediante la interfaz de iCloud, sin cuentas ni servidor propios.

## Funciones

- Autos con marca, modelo, versión y año elegidos del catálogo de [ArgAutos](https://argautos.com/docs/api), más patente y kilometraje. Las versiones se agrupan por nombre ignorando el año final, para todas las marcas y modelos. El selector de años reúne los años explícitos de esas versiones y las valuaciones de la versión base; si la consulta de valuaciones falla, se puede ingresar solo el año. Las consultas se guardan en caché durante siete días. La patente se guarda en mayúsculas y el kilometraje comienza vacío y es obligatorio para guardar. Los cambios se guardan en el iPhone aunque iCloud no esté disponible y quedan pendientes de sincronización.
- Planes con detalle libre para especificar aceite, viscosidad, marca, filtro, repuestos o instrucciones; frecuencia en meses, kilómetros o ambos.
- Planes base sugeridos para Volkswagen Taos TSI 2021–2026 (service 15.000 km/12 meses y líquido de frenos 24 meses) y Toyota Corolla 2020–2026 (service 10.000 km/12 meses). Garage los ofrece al guardar un auto compatible o desde su ficha y muestra la fuente oficial. Se pueden agregar tareas sin conocer la última realización: quedan pendientes de revisión, sin una fecha de vencimiento inventada. Cuando se conoce, se carga fecha y kilometraje para calcular el próximo aviso. Los planes importados conservan el enlace a la fuente y no se duplican.
- Recomendaciones opcionales por tarea: presión, rotación y desgaste de cubiertas; escobillas; frenos; aceite de caja; filtros de motor y habitáculo; refrigeración; correas; batería; luces y lavaparabrisas; dirección, suspensión y climatización. Cada regla distingue inspección de reemplazo y enlaza su fuente. El aceite de caja, las cubiertas y otras piezas sujetas a condición se revisan periódicamente, pero no se marcan para reemplazo automático.
- Estado próximo/vencido cuando se alcanza cualquiera de las dos condiciones.
- En «Mis autos», deslizar una fila permite eliminar un auto propio junto con sus services, o quitar de la cuenta un auto compartido por otra persona. La eliminación se guarda localmente y se sincroniza con iCloud al recuperar conexión.
- Registro de cada service con fecha, kilometraje y notas. Actualiza el próximo vencimiento.
- Notificaciones locales por fecha, al acercarse el vencimiento, y por kilometraje al ingresar una nueva lectura. Cada iPhone calcula sus propias notificaciones.
- Compartir un auto vía iCloud con permiso de lectura o edición.

## Abrir y compilar

Desde la raíz:

```sh
./scripts/workspace.sh open garage
./scripts/workspace.sh build garage
```

El script de build firma el simulador con el equipo por defecto `3SRDN9365G` (se puede reemplazar con `DEVELOPMENT_TEAM=...`). CloudKit y las notificaciones se deben probar además en iPhone firmado con un Apple Developer Team. En Xcode, asignar el equipo a `Garage`, habilitar **iCloud > CloudKit**, asociar `iCloud.com.schoren.garage` (o cambiar identificadores para el equipo propio), y activar **Background Modes > Remote notifications** si se agregan suscripciones de cambios. El contenedor debe existir en CloudKit Dashboard y el esquema debe desplegarse a producción antes de distribuir la app. Ambos participantes necesitan iCloud activo.

## Alcances actuales

Para compartir un auto, primero debe terminar de sincronizarse. El odómetro no se lee del vehículo: el usuario debe actualizarlo; una alerta por kilómetros no puede dispararse sin una lectura nueva. Los cambios de otro participante se leen al abrir la app o al deslizar para actualizar. Las plantillas son planes base, no contienen la marca o viscosidad de aceite ni todas las tareas específicas de cada versión; se debe revisar el manual del vehículo. Esta primera versión no incluye edición o borrado de planes, fotos de facturas ni avisos remotos de cambios. El entorno CloudKit real y el enlace de invitación requieren validación en dos dispositivos firmados; el simulador sólo valida compilación y UI.
