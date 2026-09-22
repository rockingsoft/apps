# Mini Apps

Workspace para mantener varias aplicaciones y herramientas pequeñas en un solo repositorio y un solo proyecto de Codex. Cada app vive de forma autónoma dentro de `apps/`: tiene su propio proyecto, código, pruebas, documentación y scripts.

## Apps

| App | Plataformas | Descripción |
| --- | --- | --- |
| [Agenda](apps/agenda/README.md) | macOS, iOS, iPadOS | Calendario y recordatorios con widgets nativos. |
| [Paleta](apps/paleta/README.md) | macOS | Paleta global para buscar y ejecutar comandos de la app activa. |

La lista se puede consultar sin abrir ningún proyecto:

```sh
./scripts/workspace.sh list
```

## Trabajar con una app

Los comandos se ejecutan siempre desde la raíz y se delegan a la app elegida:

```sh
./scripts/workspace.sh test agenda
./scripts/workspace.sh build agenda
./scripts/workspace.sh open agenda
./scripts/workspace.sh generate agenda
```

`./scripts/workspace.sh check` valida la estructura de todas las apps. `./scripts/workspace.sh all test` ejecuta un comando en cada app que lo implemente.

## Agregar una mini-app

```sh
./scripts/workspace.sh new mi-herramienta "Mi herramienta"
```

Esto crea `apps/mi-herramienta/` con un manifiesto, documentación y carpetas iniciales. Después se agrega el proyecto propio de esa app y scripts ejecutables en `apps/mi-herramienta/scripts/`. Los nombres estandarizados que entiende el workspace son `test.sh`, `build.sh`, `open.sh` y `generate.sh`.

Reglas de organización:

- Una app no importa código de otra app directamente.
- Cada app puede usar tecnologías, dependencias y estructuras completamente distintas.
- Los identificadores, entitlements, artefactos de build y configuración de firma pertenecen a cada app.
- La raíz contiene únicamente orquestación y documentación transversal; no targets de producto.

No hace falta crear otro proyecto de Codex: se abre esta raíz y se indica la app sobre la que se quiere trabajar.
