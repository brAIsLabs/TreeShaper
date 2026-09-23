# Arquitectura

## Visión general

TreeShaper inventaría directorios locales y de red (fileservers Windows/NTFS) y permite planificar su reestructuración de forma virtual: clasificar elementos, proponer movimientos, fusiones y carpetas nuevas, y anonimizar nombres. Es un prototipo en PowerShell + HTML: genera planes, pero no ejecuta ninguna operación sobre el disco.

## Componentes

- **`Inventario-Rutas.ps1`** (PowerShell ≥ 5.1). Escáner de solo lectura. Recorre de forma recursiva la ruta indicada (local, UNC o unidad mapeada) y escribe un JSON UTF-8 sin BOM (`schemaVersion 1`) con:
  - `meta`: ruta raíz, fecha, usuario, máquina, versión de PowerShell, totales y `errores`.
  - `tree`: carpetas y ficheros con nombre, ruta, tamaño, fecha de modificación y recuentos.

  Reintenta con prefijo `\\?\` las rutas largas y registra en `meta.errores` lo que no puede leer, sin abortar. Pide confirmación S/N antes de empezar.

  No sigue junctions ni enlaces simbólicos (detectados por `LinkType`; si no se puede leer, tampoco desciende). Los guarda como nodo `folder` sin hijos, con `size` 0 y el campo opcional `linkType`, y los anota en `meta.errores` como "Enlace no seguido (tipo): ruta -> destino". Si `LinkType` no se puede leer, el nodo lleva `linkType` "Desconocido", el aviso es "Enlace no identificado: ruta -> destino" y cuenta como ruta no leída. Otros reparse points (enlaces DFS, archivos en la nube, deduplicación) se recorren con normalidad; los puntos de montaje de volumen probablemente se tratan como junction. El comportamiento en UNC, DFS y puntos de montaje es una hipótesis sin verificar en un entorno real. La ruta raíz se escanea aunque sea un enlace. `schemaVersion` sigue en 1: el campo es opcional y el HTML lo ignora (hoy no lo conserva al guardar la versión de trabajo).
- **`Organizador-Rutas.html`** (HTML + JavaScript en un solo archivo, sin dependencias). Carga uno o varios JSON y los muestra como ramas de un árbol único. Todo ocurre en la memoria del navegador:
  - Estados por elemento: Mantener, Revisar, Reubicar, Eliminar.
  - Operaciones virtuales: mover (deja un alias en el destino), fusionar carpetas (crea una carpeta nueva que contiene ambas como alias), crear y renombrar carpetas nuevas, y deshacer movimientos. Se puede operar entre informes distintos.
  - Anonimización por carpeta: capa 1 (email, IBAN, DNI, NIE y teléfono, por expresión regular) y capa 2 (nombres de persona, por lista de nombres).
  - Vistas: filtros por estado, estructura propuesta, solo carpetas y búsqueda por nombre.
  - Exportaciones (descargas del navegador): versión de trabajo (JSON, recargable), versión anonimizada (JSON, sin usuario, máquina ni errores), plan de estructura (CSV con CREAR_CARPETA, FUSIONAR, MOVER y ELIMINAR) y acciones por estado (CSV).
- **Comunicación:** por archivo. El JSON del script se carga a mano en el HTML; no hay servidor, base de datos ni proceso compartido.

## Flujo principal

```
Inventario-Rutas.ps1 -Ruta X -Salida Y
  └─ confirmación S/N → escaneo recursivo (solo lectura) → Y\inventario_AAAAMMDD_HHMMSS.json

Organizador-Rutas.html
  └─ cargar uno o varios JSON → árbol único en memoria
     → marcar estados / mover / fusionar / crear carpetas / anonimizar
     → exportar plan_estructura_*.csv (y, si se quiere, la versión de trabajo en JSON)

Fin: el plan no lo ejecuta nadie; no existe motor de ejecución.
```

## Límites y dependencias externas

- Windows; rutas NTFS locales, UNC (`\\servidor\recurso`) o unidades mapeadas.
- PowerShell 5.1 o superior (PowerShell 7 reduce los errores por rutas largas).
- Navegador moderno (FileReader, Blob). Sin librerías externas.
- Únicas escrituras en disco: el JSON que genera el script en `-Salida` (obligatorio; se resuelve a ruta absoluta y se muestra en la confirmación) y las descargas del navegador.
- Fuera del alcance actual: ejecutar operaciones sobre el disco (DELETE, MOVE, MERGE, etc.) y la operación ANALYZE, que todavía no existe en el código.

## Evolución prevista

- **Migración a .NET + SQLite.**
- **Objetivo:** que la aplicación cubra el flujo completo dentro de .NET: análisis → reestructuración virtual → ejecución de los cambios en los servidores de ficheros.
- **Descartado:** generar desde el HTML un script `.ps1` que aplique los cambios. Quedaría fuera de la aplicación real, y un `.ps1` podría dar problemas en entornos empresariales, lo que pone en duda que llegara a usarse.
- **Principio innegociable del motor de ejecución.** Ninguna operación que escriba en disco (borrar, mover, fusionar, renombrar, crear carpetas, sobrescribir o cambiar atributos o permisos) se ejecutará sin pasar, en este orden, por:
  1. **Propuesta:** el usuario, una regla o una IA sugiere la acción. Es solo una intención registrada y nunca toca el disco.
  2. **Validación:** el código comprueba que la acción es posible y segura (el origen existe, el destino es válido, no sobrescribe nada, hay permisos).
  3. **Preview:** se muestra al usuario exactamente qué va a ocurrir.
  4. **Confirmación:** el usuario la aprueba de forma explícita.
  5. **Ejecución:** solo el motor de ejecución modifica el disco, y solo después de la confirmación.

  El escaneo y el análisis, que solo leen, quedan fuera.
