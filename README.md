# TreeShaper

Herramienta para inventariar directorios locales y de red (fileservers Windows/NTFS) y planificar su reestructuración de forma virtual, con un marcado por etiquetas. Pensada para los departamentos IT de pequeñas y medianas empresas.

**Estado:** prototipo en PowerShell + HTML. Hay prevista una migración a .NET + SQLite.

> TreeShaper no modifica los datos que analiza. El escáner solo lee (lo único que escribe es el JSON en la carpeta de salida), y el plan de reestructuración se exporta como CSV: todavía no hay nada que lo ejecute.

## Qué hace

1. **`Inventario-Rutas.ps1`** recorre una carpeta (local, UNC o unidad mapeada) y genera un JSON con su árbol: carpetas, ficheros, tamaños y fechas de modificación.
2. **`Organizador-Rutas.html`** carga uno o varios de esos JSON en el navegador y permite:
   - clasificar cada elemento (Mantener, Revisar, Reubicar, Eliminar);
   - mover, fusionar, crear y renombrar carpetas de forma virtual;
   - anonimizar nombres (emails, IBAN, DNI/NIE, teléfonos y nombres de persona);
   - exportar la versión de trabajo (JSON), una versión anonimizada (JSON), el plan de estructura (CSV) y las acciones por estado (CSV).

Todo ocurre en local. No hay servidor, instalación ni dependencias externas.

## Requisitos

- Windows con PowerShell 5.1 o superior (recomendado PowerShell 7, que maneja mejor las rutas largas).
- Un navegador moderno.

## Uso

1. Descarga o clona el repositorio. Si lo descargaste como `.zip`, desbloquea el script: Windows marca los archivos descargados de Internet y la directiva `RemoteSigned` impide ejecutarlos.

   ```powershell
   Unblock-File .\Inventario-Rutas.ps1
   ```

2. Inventaría una ruta:

   ```powershell
   pwsh -File .\Inventario-Rutas.ps1 -Ruta "\\SRV\Recurso\Carpeta" -Salida "C:\Inventarios"
   ```

   El script muestra lo que va a hacer, pide confirmación (S/N) y genera `inventario_AAAAMMDD_HHMMSS.json` en la carpeta de salida.

3. Abre `Organizador-Rutas.html` en el navegador y carga el JSON.

### Parámetros

| Parámetro | Obligatorio | Descripción |
|---|---|---|
| `-Ruta` | Sí | Carpeta que se inventaría: local (`D:\Datos`), UNC (`\\servidor\recurso`) o unidad mapeada. |
| `-Salida` | Sí | Carpeta donde se guarda el JSON. Si no existe, se crea. |
| `-IncluirOcultos` | No | Incluye los elementos ocultos y de sistema. |
| `-Profundidad <n>` | No | Profundidad máxima de recorrido. Por defecto, sin límite. |

Ayuda completa: `Get-Help .\Inventario-Rutas.ps1 -Full`.

## Privacidad

El JSON del inventario incluye el usuario que lo generó, el nombre del equipo, las rutas completas y los errores de lectura. Trátalo como información interna.

La exportación anonimizada del HTML quita el usuario, el equipo y los errores, y anonimiza los nombres de las carpetas que marques. **No es una anonimización completa:** conserva la ruta raíz, los nombres que no anonimices y, en los elementos movidos, las rutas originales y de destino y los nombres de los alias. Revísala antes de compartirla fuera de IT.

## Limitaciones conocidas

- La confirmación es interactiva: el script no se puede ejecutar desatendido.
- No sigue junctions ni enlaces simbólicos, para evitar bucles y duplicados. Los muestra como carpetas vacías y los lista en los errores del informe. Si quieres su contenido, inventaría el destino como ruta propia. Los enlaces DFS y las carpetas en la nube deberían recorrerse con normalidad, pero no se ha verificado todavía en un entorno real; tampoco con junctions vistas a través de UNC. Si el script no puede identificar un enlace, no entra en él y lo cuenta como ruta no leída.
- Los enlaces duros se cuentan una vez por cada nombre.
- En los CSV exportados, las celdas que empiezan por `=`, `+`, `-` o `@` llevan un `'` delante para que Excel no las ejecute como fórmulas. En Excel no se ve; en un editor de texto, sí.
- Un informe con rutas de más de 260 caracteres puede tener errores de lectura en PowerShell 5.1. Con PowerShell 7 son mucho menos frecuentes.

## Licencia

[GNU Affero General Public License v3.0 o posterior](LICENSE) (`AGPL-3.0-or-later`). Copyright (C) 2026 brAIsLabs.

Puedes usar, estudiar, modificar y redistribuir TreeShaper, también con fines comerciales, siempre que cualquier versión que distribuyas, o que ofrezcas a otros a través de una red, se publique con su código fuente y bajo la misma licencia.

## Documentación

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): cómo está construido TreeShaper y hacia dónde va.
- [`docs/security.md`](docs/security.md): estado de seguridad, con lo que está abierto y lo que ya se ha corregido.
