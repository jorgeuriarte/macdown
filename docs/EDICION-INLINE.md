# Edición inline por bloques — especificación de interacción

> Diseño de la edición inline de MacDown Remix (corresponde a **M1** del
> [`ROADMAP.md`](ROADMAP.md): "Edición inline por bloques"). Este documento fija el
> **modelo de interacción** acordado; la implementación es posterior.
>
> Prototipo navegable de referencia: [`prototypes/edicion-inline.html`](prototypes/edicion-inline.html)
> (ábrelo en un navegador). Lo aquí escrito y el prototipo deben ir a la par.

## 1. Objetivo y premisa

Permitir **editar el documento desde el visor**, bloque a bloque, sin renunciar a las
ventajas de escribir Markdown. La premisa explícita: **no es un WYSIWYG puro** (tipo
Notion/Typora "live"), porque Markdown gana al escribir (velocidad, control, portabilidad).

La salida elegida es un **híbrido**: el visor sirve para **seleccionar** el bloque al
nivel que quieras (interacción visual, inmediata), pero **editas su Markdown fuente** (no
el render rico). Lo mejor de los dos mundos. Aprovecha que tenemos **split editor+visor**
(cosa que Typora no tiene): el fuente está siempre disponible al lado.

## 2. El problema que resuelve: el anidamiento

El Markdown es jerárquico (Sección ⊃ párrafo ⊃ lista ⊃ ítem ⊃ código inline). Al
apuntar a un punto del documento hay **varios bloques candidatos**. El modelo debe dejar
**elegir el nivel** sin imponerlo: unos editan bloques grandes, otros pequeños.

La solución es **selección estructural explícita** (modelo *inspector de DevTools*), no el
"el cursor navega y ya" de un editor de texto rico.

## 3. Modelo de interacción (lo acordado)

### 3.1 Activación deliberada — la franja
- Una **franja vertical** siempre visible en el **borde derecho del texto** (~últimas
  columnas del ancho útil), con un degradado tenue + borde punteado: es la *affordance*
  de "aquí se edita". **Mientras lees, nada se mueve.**
- Al acercar el ratón a esa franja, **despierta** el modo inspector (la franja se
  intensifica).

### 3.2 Hover = preview · clic = fijar
- **Hover** dentro de la franja → recuadro tenue sobre el **bloque a esa altura** + una
  **etiqueta flotante** con el tipo de bloque y su rango de líneas (`¶ Párrafo · L5`).
- **Clic** → **fija** el bloque (recuadro sólido de cuatro esquinas — el estilo ya
  decidido, ver más abajo). Fijar lo hace **estable** para poder interactuar sin perderlo.

### 3.3 Elegir el nivel (el anidamiento)
Una vez fijado:
- **Breadcrumb** inferior con la jerarquía (`§ Documento › ▤ Sección › • Lista › – Ítem`);
  pasar el ratón por un nivel sube el recuadro a ese bloque; clic lo elige.
- **Teclado:** `←/→` suben/bajan de nivel; `↑/↓` saltan al bloque anterior/siguiente del
  mismo nivel. (Las flechas **solo operan una vez fijado**.)

### 3.4 Editar
- **Doble-clic (estando ya fijado)** o el **botón ✏︎** (icono circular sutil, esquina
  superior derecha del bloque) → abre el bloque como **mini-editor de su Markdown fuente**
  (con Cancelar / Hecho).
- El doble-clic se exige **sobre un bloque ya fijado** a propósito: evita que, en un
  doble-clic "en frío", el cursor se mueva entre los dos clicks y se fije/edite un bloque
  distinto.

### 3.5 Soltar
- Se suelta al **salir del bloque fijado** (por arriba, abajo, derecha o izquierda), con
  un pequeño *grace* anti-parpadeo al rozar el borde. **Esc** también suelta.
- La zona "viva" es el **bloque fijado + su botón**, no toda la franja.

## 4. El editor de bloque

- Muestra el **Markdown fuente** del bloque (resaltado), **no** un editor rico.
- Al confirmar (**Hecho**): re-render del documento y **reescritura del rango exacto** del
  fuente correspondiente (vía `sourcepos`).
- El **panel editor de Markdown completo no desaparece**: sigue siendo la vía de edición
  masiva. La edición inline es una **capa adicional**, no un reemplazo. Un único modelo de
  verdad: ambos editan **el mismo fuente**.

## 5. Estilo del recuadro (ya implementado en el visor)

Reutiliza lo ya hecho en la selección conectada:
- **Cuatro esquinas** (+ trazo central en bloques grandes), **color del tema** (acento del
  CSS en el visor), **aire interior**. Ver `docs/DIARY.md` (2026-06-19).

## 6. Encaje técnico (qué ya tenemos)

| Pieza | Estado | Rol en la edición inline |
|---|---|---|
| `CMARK_OPT_SOURCEPOS` (`data-sourcepos` por bloque) | ✅ activo | mapa **bloque ↔ rango exacto del fuente** |
| Puente `WKScriptMessageHandler` | ✅ | clic/hover en el visor → ObjC |
| Recuadro del bloque activo (visor + editor) | ✅ | selector visual / fijación |
| Selección conectada por bloque | ✅ | base de "apuntar al bloque y reflejarlo" |

## 7. Gap conocido a resolver: las **secciones** no están en el AST

cmark-gfm produce bloques **hermanos planos**: `<h2>`, `<p>`, `<ul>`, `<h2>`… La "sección"
(un heading + todo su contenido hasta el siguiente heading de nivel ≤) **no es un nodo del
AST ni un elemento del HTML** — es un **rango implícito**. Sin embargo, el modelo de niveles
(breadcrumb, `←/→`) necesita la "Sección" como un nivel navegable.

Hay que **construir el árbol de secciones** a partir de los headings y su `sourcepos`
(agrupar los bloques entre dos headings, respetando el anidamiento H1>H2>H3). Las opciones
y su evaluación están **pendientes de investigar** (envolver en `<section>` en post-proceso
del HTML vs. calcular el rango en ObjC/JS al seleccionar). Es el siguiente análisis.

## 8. Pendientes / riesgos

- **Construcción de secciones** (gap §7).
- **Re-render**: tras Hecho, ¿re-render de todo el doc o solo del bloque? Empezar por todo.
- **Ediciones que cambian la estructura** (un párrafo que pasa a lista): el re-mapeo de
  `sourcepos` se complica; recalcular.
- **Transición visual** del mini-editor (que no "salte").

## 9. Hito de implementación sugerido (acotado)

Portar al visor: **hover/fijar/breadcrumb sobre `sourcepos`** + abrir el **fuente del
bloque** en un editor inline, dejando para después el re-render fino y las ediciones que
cambian estructura.
