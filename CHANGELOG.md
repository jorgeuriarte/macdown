# Changelog — MacDown Remix

Cambios relevantes, agrupados por bloque funcional (no commit a commit). El proyecto es un
fork de mantenimiento de [MacDown](https://github.com/MacDownApp/macdown) sobre **cmark-gfm
+ WKWebView**.

## [Sin publicar] — Edición inline (M1) + rendimiento

### Edición inline por bloques (M1) — nuevo, experimental
Editar el documento **desde el visor**, sin renunciar a Markdown (no es WYSIWYG: se edita el
fuente). Vive en **modo sólo-visor**, su hogar único.

- **Modo escritura activable**: por defecto el visor es para **leer** (limpio, sin ruido).
  En sólo-visor aparece un **botón flotante ✎** (esquina superior derecha) que enciende el
  modo escritura; la toolbar de formato se oculta en ese modo.
- **Selección espacial "fondo de sección"**: la **altura** del ratón en la franja de
  activación (borde derecho) elige el bloque (ítem, párrafo, título). **Clic en la etiqueta
  del fondo** (`• Lista`, `▤ Sección`) sube al contenedor: ítem → lista → sección →
  documento. Sin breadcrumb, sin flechas, sin doble-clic mágico.
- **Secciones al vuelo** (Opción D): la "sección" (heading + su contenido) se calcula desde
  los headings y `data-sourcepos`, **sin crear `<section>` ni tocar el render de cmark**.
- **Mini-editor in situ**: ✏︎ / doble-clic (con el bloque fijado) abre el **Markdown fuente**
  del bloque, con botón **Vista previa** renderizado con el **mismo motor** (cmark). Al
  confirmar, reescribe el **rango exacto** del fuente (vía `sourcepos`) con **undo** y
  re-renderiza. El ✏︎ sólo aparece una vez fijado el bloque.
- **Franja de activación** anclada a la columna del texto (una tabla/`<pre>` anchos ya no la
  arrastran), con gradiente hasta el borde de la ventana y el ✏︎ junto a la línea.
- **Máquina de estados** única (`off/reading/idle/hover/pinned/editing`) con un solo mutador,
  que hace imposibles por construcción los estados ilegales (p. ej. desactivar la edición con
  el editor abierto).

### Sincronización fuente↔visor
- Las **esquinas** reflejan en el visor el bloque del cursor del editor, y seleccionar en el
  visor lleva el cursor del editor al bloque. Bidireccional y pasiva (acompaña la edición
  tradicional); convive con cualquier modo.

### Rendimiento
- **MathJax sólo en documentos con fórmulas**: antes se descargaba la librería del CDN en
  **todos** los documentos (red en el primer render, incluso en docs simples). Ahora se
  carga solo si el documento contiene `\(…\)` o `$$…$$` (como ya hacía Mermaid). Primer
  render mucho más rápido en documentos sin matemáticas.

### Arreglos
- **Esc** cancela el mini-editor también en **Vista previa** (antes solo con el textarea
  enfocado).
- El **modo escritura no se desactiva con el editor abierto**; cambiar de modo de vista o
  salir de sólo-visor **cierra** el editor en vez de dejarlo colgado.
- Corregido el **"inspector congelado"** cuando la etiqueta del fondo se ocultaba con el
  ratón encima.

## [1.0-beta.1] — Línea única cmark-gfm + WKWebView

Convergencia a una sola línea de producto y primer canal de release propio.

- **Motor cmark-gfm** (CommonMark + GFM) con AST y `sourcepos` por bloque; **preview en
  WKWebView** moderno (puente `WKScriptMessageHandler`). Identidad propia
  ("MacDown Remix", bundle `net.omelas.macdown-remix`); la línea hoedown se archiva como tag.
- **Saneamiento**: arranca y compila en macOS/Apple Silicon actuales (fix del crash de
  arranque del toolbar, deployment target, arm64). CI reproducible en GitHub Actions.
- **Funcionalidad**: math (MathJax) con protección de fórmulas y saltos de fila en matrices;
  anclas de heading (slug GitHub + `[TOC]`); recuperación de resaltado `==` y superíndice
  `^`; **buscador en el visor** (Cmd+F) y **selección conectada por bloque**; recuadro de
  bloque (cuatro esquinas + dash, color por tema); CLI `macdown` autónoma (symlink propio,
  no depende del cask original); canal de release propio (appcast EdDSA, instalación manual
  mientras no haya Developer ID).
