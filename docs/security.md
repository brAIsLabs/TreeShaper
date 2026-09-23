# Estado de seguridad

Foto del estado de seguridad de TreeShaper: qué está abierto, qué se ha cerrado y qué riesgos se aceptan.

Última revisión: 2026-09-23 (primera revisión completa del escáner y del HTML, antes de publicar).

## Hallazgos abiertos

| ID | Severidad | Resumen | Ubicación | Detectado |
|---|---|---|---|---|
| SEC-009 | media | La exportación anonimizada conserva datos reales en `planAlias.srcPath`, `planMovedTo`, `relocateTo` y en el `name` de los alias (`anonApply` se salta los `_alias`). README corregido para no prometerlo; falta la corrección en el código | `Organizador-Rutas.html`, `exportAnonNode`, `doMove`, `anonApply` | 2026-09-23 |
| SEC-010 | baja | Nombres de carpeta del usuario sin validar (`\`, `/`, `..`, reservados, espacio o punto final): el CSV del plan puede contener destinos que escapan del recurso. Requisito del futuro motor de ejecución: revalidar y canonicalizar cada ruta, sin confiar en el CSV ni en el JSON | `Organizador-Rutas.html`, `makeNewFolder`, `nfOk`, `renameFolder`, `resolveDest`, `mergeOk` | 2026-09-23 |
| SEC-011 | baja | Escritura de la salida: `WriteAllText` sobrescribe si existe el mismo `inventario_<timestamp>.json`; `New-Item -Path` interpreta `[` `]`; `-Salida` solo se valida tras el escaneo (se pierde el trabajo si no se puede escribir); un proveedor que no es FileSystem (`HKCU:\`) no da ruta absoluta | `Inventario-Rutas.ps1`, resolución de `-Salida` y escritura final | 2026-09-23 |
| SEC-012 | baja | Sin Content-Security-Policy en el HTML (defensa en profundidad; hoy no hay XSS) | `Organizador-Rutas.html`, `<head>` | 2026-09-23 |
| SEC-013 | baja | Reparse points que no son junction ni enlace simbólico (DFS, `LinkType` nulo) se recorren sin control de ciclos. Si `LinkType` devuelve `$null` al fallar, un enlace se seguiría. Sin verificar en UNC ni DFS | `Inventario-Rutas.ps1`, `New-NodoCarpeta` | 2026-09-23 |
| SEC-014 | media | Un enlace se ve en la interfaz como carpeta vacía normal: se le puede proponer Eliminar o Mover, o usarlo como destino; `cleanNode` y `exportAnonNode` descartan `linkType`. Requisito del futuro motor: no borrar nunca de forma recursiva a través de un reparse point y recomprobar origen, destino y ancestros antes de ejecutar | `Organizador-Rutas.html`, `cleanNode`, `exportAnonNode`; `Inventario-Rutas.ps1` | 2026-09-23 |
| SEC-015 | baja | Enlaces simbólicos a archivo no se marcan (tamaño del enlace, sin `linkType`); puntos de montaje salen como "Junction" y destinos `UNC\...` sin `\\` inicial | `Inventario-Rutas.ps1`, `New-NodoCarpeta` | 2026-09-23 |

## Cerrados recientemente

- SEC-008 (2026-09-23): inyección de fórmulas en los CSV. `csvCell` antepone `'` a las celdas que empiezan por `=`, `+`, `-`, `@`, tabulador o CR. Efecto visible: esos nombres aparecen con `'` delante fuera de Excel. Verificado con 13 casos sobre la función real.

## Riesgos aceptados

Riesgos conocidos que el humano ha decidido no corregir por ahora, con su motivo.

- Ninguno.
