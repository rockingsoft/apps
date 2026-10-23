# Garage — services del auto

App nativa SwiftUI para iPhone/iPad (iOS 17+) que guarda autos, planes de servicio e historial en CloudKit. Cada auto tiene una zona privada separada para compartir sólo ese auto con otra persona mediante la interfaz de iCloud, sin cuentas ni servidor propios.

## Funciones

- Autos con nombre, patente y kilometraje actual. Los cambios se guardan en el iPhone aunque iCloud no esté disponible y quedan pendientes de sincronización.
- Planes con detalle libre para especificar aceite, viscosidad, marca, filtro, repuestos o instrucciones; frecuencia en meses, kilómetros o ambos.
- Estado próximo/vencido cuando se alcanza cualquiera de las dos condiciones.
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

Para compartir un auto, primero debe terminar de sincronizarse. El odómetro no se lee del vehículo: el usuario debe actualizarlo; una alerta por kilómetros no puede dispararse sin una lectura nueva. Los cambios de otro participante se leen al abrir la app o al deslizar para actualizar. Esta primera versión no incluye edición o borrado de planes, fotos de facturas ni avisos remotos de cambios. El entorno CloudKit real y el enlace de invitación requieren validación en dos dispositivos firmados; el simulador sólo valida compilación y UI.
