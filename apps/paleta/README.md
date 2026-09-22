# Paleta

Paleta de comandos global para macOS. Con `⇧⌘P`, lee los menús de la aplicación activa mediante la API de Accesibilidad, permite buscar con coincidencia difusa y ejecuta el comando elegido.

## Probar

```sh
./scripts/workspace.sh test paleta
./scripts/workspace.sh build paleta
./scripts/workspace.sh open paleta
```

La primera vez, macOS solicita habilitar **Paleta** en Configuración del Sistema → Privacidad y seguridad → Accesibilidad. Después de conceder el permiso, cerrá y volvé a abrir la app.

## Alcance del MVP

- Atajo global `⇧⌘P`.
- Comandos habilitados del menú de la app que estaba activa.
- Búsqueda difusa por nombre y ruta del menú.
- Visualización del atajo original.
- Navegación con flechas, ejecución con `Return` y cierre con `Escape`.
- Historial persistente por aplicación: los comandos ejecutados recientemente aparecen primero y reciben prioridad en la búsqueda.

El nombre, el diseño y el código son propios; Paletro se usa únicamente como referencia funcional.

## Distribución

Los releases públicos se firman con Developer ID, se notarizan con Apple y se publican en GitHub. El canal Homebrew oficial de RockingSoft es:

```sh
brew install --cask rockingsoft/tap/paleta
```

El workflow de release requiere los secretos `APPLE_CERTIFICATE_P12`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_APP_PASSWORD`, `APPLE_TEAM_ID` y `KEYCHAIN_PASSWORD`. La publicación se activa con un tag semántico con namespace, por ejemplo `paleta-v0.1.0`.
