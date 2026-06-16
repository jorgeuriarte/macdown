# ROADMAP — MacDown Remix (post-1.0-beta)

> Mini-roadmap priorizado de mejoras para **MacDown Remix**, el fork de
> mantenimiento de MacDown con motor **cmark-gfm** (AST + `sourcepos`) y preview en
> **WKWebView** (puente JS↔ObjC vía `WKScriptMessageHandler`, scroll-sync
> bidireccional). Documento de planificación; no implementa nada.

_Generado el 2026-06-15. Fundamentado en: (a) lo que aportan los forks de la
comunidad (`docs/FORKS.md`, `docs/CREDITS.md`, `CLAUDE.md` §4), (b) los issue
trackers, y (c) buenas prácticas de editores Markdown modernos (Typora, Obsidian,
iA Writer, Mark Text, Zettlr, Marked 2)._

---

## 0. Nota metodológica sobre las fuentes

**Issue trackers — qué hay disponible de verdad (sé honesto):**

- **El único tracker accesible y con señal es el del original
  [`MacDownApp/macdown`](https://github.com/MacDownApp/macdown)** (~9.7k ⭐, 1146
  forks). Tiene cientos de issues; muchos feature-requests históricos siguen
  vigentes porque el original lleva sin tocarse desde julio de 2023 (ver issue
  **#1335 "Project Status? Successor?"**, **#1357 "Try out MacDown 3000?"**).
- **TODOS los forks activos tienen los issues DESHABILITADOS**: `plateaukao`,
  `SiggeMcKvack`, `nyimbi`, `RezaAmbler/macdown_arm`, `xhu96`, `duro`,
  `Wirtzer/Markly`, `mfbergmann/macdown-swift`. No se puede leer "qué piden" en
  ellos; solo se infiere su aporte por sus commits (vía `docs/FORKS.md`).
- **`treehousetim/macdown`** tiene los issues habilitados pero **0 issues**
  (abiertos o cerrados).

Conclusión: la demanda de usuario se reconstruye desde el tracker del original;
el "qué aporta cada fork" desde sus commits. Donde cito un número de issue, es de
`MacDownApp/macdown` salvo indicación contraria.

**Marca de procedencia usada en las tablas:**

- 🍴 = viene de un fork concreto de la comunidad (con commits reales).
- 🗳️ = pedido recurrente en el tracker del original (con nº de issue).
- 🧭 = buena práctica estándar de editores Markdown modernos.
- 🔒 = **Markly (fork cerrado, "all rights reserved")**: SOLO inspiración,
  **reimplementar desde cero**, no mergear ni copiar código.

**Encaje con la ventaja arquitectónica del proyecto:**

- **AST + `sourcepos`** → habilita mapeo bloque↔texto: outline fiable, scroll-sync
  por nodo, y a futuro edición inline por bloques.
- **Puente `WKScriptMessageHandler`** → canal natural para acciones contextuales,
  UI interactiva en el preview y, a futuro, IA.

---

## 1. Quick wins (alto valor / bajo esfuerzo)

Orden = primero lo de mejor relación valor/esfuerzo.

| # | Mejora | Qué es | Procedencia | Valor | Esfuerzo | Encaje AST/puente |
|---|---|---|---|---|---|---|
| Q1 | **Recarga automática en cambio externo** | Detectar que el `.md` cambió en disco y recargar (o avisar si hay cambios sin guardar). | 🍴 treehousetim (`1b42ba3`, ya **integrada** según `CREDITS.md`) · 🗳️ #1372, #630, #1185, #1085 | Alto | S | — |
| Q2 | **Strike-through `~~texto~~`** | Tachado GFM en el render. | 🗳️ #1324 · 🧭 GFM estándar | Alto | S | cmark-gfm lo trae nativo (extensión `strikethrough`); es activarlo |
| Q3 | **Zoom de fuente con ⌘+ / ⌘- / ⌘0** | Escalar editor y preview con atajos, no solo CSS. | 🍴 RezaAmbler (`9d27a8f`, ya **integrada**) · 🗳️ #1304 | Alto | S | puente: aplicar zoom al WKWebView |
| Q3b | **Escalar imágenes anchas al ancho de ventana** | `max-width:100%` opcional en imágenes grandes del preview. | 🗳️ #1311 · 🧭 común | Alto | S | CSS de tema; trivial |
| Q4 | **Wrap de líneas largas en bloques de código** | Code wrapping opcional en preview (y sin recorte al exportar PDF). | 🗳️ #1350, #1136, #1196 | Alto | S | CSS/preview |
| Q5 | **Pegar/arrastrar imagen → enlace de fichero** | Al pegar/soltar imagen, guardarla junto al doc e insertar `![](ruta)` en vez de incrustar datos crudos. | 🗳️ #1295 · 🧭 esperado en todos los editores modernos | **Alto** | M | editor + FS; muy demandado |
| Q6 | **Arreglar "Open Recent" (entradas null)** | Lista de recientes con entradas en blanco que dan _"document (null) could not be opened"_. | 🗳️ **#1334 (16 comentarios, el issue más comentado)**, #1356, #1330 · 🍴 igorschlum "Restore OpenRecent", trailblazr | **Alto** | S | bug de calidad; alta visibilidad |
| Q7 | **Mermaid v11 al día** | Versión moderna de Mermaid (más tipos de diagrama, no rompe diagramas siguientes). | 🍴 plateaukao (`mermaid v11`, **es nuestra base**) · 🗳️ #1341, #1343 | Alto | S | confirmar que la base lo trae bien |
| Q8 | **Modos de vista Light/Dark/Sepia + tema oscuro de preview** | Conmutador de tema de preview, incl. dark que respete el sistema. | 🍴 RezaAmbler (ya **integrada**) · 🍴 sigge (GitHub Dark, GitLab light/dark) · 🗳️ #1307, #1300 | Medio | S | CSS/temas |
| Q9 | **Continuación inteligente de listas** | Enter en lista crea el siguiente `- `/`1.`; numeración auto-incrementa; Enter en línea vacía cierra la lista. | 🗳️ #1279 · 🧭 estándar (Typora/Obsidian) | Alto | M | editor; mejor con AST para saber el contexto del bloque |
| Q10 | **Word count / estadísticas de escritura** | Contador de palabras/caracteres/tiempo de lectura; idealmente de la selección. | 🗳️ #370, #436, #1239, #1031, #812 · 🔒 Markly ("writing stats") | Medio | M | barra de estado |
| Q11 | **Soporte de text-replacements del sistema** | Que funcionen las sustituciones de _Ajustes → Teclado → Texto_ en el editor. | 🗳️ #1278 (5 comentarios) | Medio | M | editor (`NSTextView`) |
| Q12 | **Quick Look Preview Extension (.md en Finder)** | Previsualizar `.md` con la barra espaciadora desde Finder. | 🍴 treehousetim (`Quick Look Preview Extension target`) · 🗳️ **#1366 (9 comentarios)** | Alto | M | requiere _target_ nuevo en el `.xcodeproj` (no cherry-pickea limpio, ver `CREDITS.md`) |

**Por qué este bloque primero:** casi todo es CSS/preview, bugs de calidad o
features que cmark-gfm ya soporta. Varios (Q1, Q3, Q8) **ya están integrados** —
aquí quedan como verificación/cierre. Q2 es prácticamente gratis con cmark-gfm.

---

## 2. Features grandes

Orden = primero lo de mayor valor con esfuerzo asumible.

| # | Mejora | Qué es | Procedencia | Valor | Esfuerzo | Encaje AST/puente |
|---|---|---|---|---|---|---|
| F1 | **Outline / TOC navegable en sidebar** | Panel lateral con la jerarquía de encabezados; clic salta a la sección; resaltado de la sección activa. | 🍴 RezaAmbler ("TOC heading links", ya **integrada** parcial) · 🔒 Markly ("sidebar", "outline navigation") · 🗳️ #62 "TOC Navigator", #1042 · 🧭 estándar | **Alto** | M | **🎯 Encaje fuerte**: el AST da la jerarquía de headings con `sourcepos` exacto → navegación fiable sin parsear texto |
| F2 | **Find & Replace con regex** | Buscar/reemplazar robusto, con expresiones regulares y reemplazo en todo el doc (no solo selección). | 🗳️ #1123 (regex), #707 (bug: solo reemplaza selección), #560 | **Alto** | M | editor |
| F3 | **Export DOCX / PPTX (+ presets y portadas)** | Exportar a Word/PowerPoint con plantillas. | 🍴 **nyimbi** (`MPOfficeExporter`, `MPExportOptions`, 12 commits — candidata en `CREDITS.md`) · 🗳️ export es de los temas más pedidos | Alto | L | épica propia; el AST facilita un exporter limpio |
| F4 | **Mejoras de export PDF** | Números de página, sin líneas en blanco aleatorias, sin recorte de código. | 🗳️ #1291, #1299, #1196, #1350 | Medio | M | preview/print |
| F5 | **Modo carpeta / Browse mode** | Abrir una carpeta (`docs/`), sidebar con el árbol de ficheros `.md`, navegación entre ellos, clic en enlace local abre el fichero. | 🗳️ **#1336 + #1358** (dos issues independientes pidiendo lo mismo) · 🔒 Markly ("sidebar", "tabs") · 🧭 Obsidian/VS Code | **Alto** | L | base para WikiLinks (F6) y para "vault"/proyecto |
| F6 | **WikiLinks `[[nota]]`** | Enlaces internos entre documentos; navegación; marcar destino inexistente. | 🔒 **Markly** ("WikiLinks", reimplementar) · 🧭 Obsidian/Zettlr | Alto | M | mejor sobre F5 (modo carpeta); extensión del AST de enlaces |
| F7 | **Command Palette (⌘K / ⌘⇧P)** | Paleta de comandos difusa para acciones y navegación. | 🔒 **Markly** ("Command Palette", reimplementar) · 🧭 VS Code/Obsidian | Alto | M | puente: lista de acciones; sinergia con outline (F1) |
| F8 | **Focus mode + Typewriter mode** | Resaltar solo el párrafo/frase activa; mantener el cursor centrado verticalmente. | 🔒 **Markly** ("Focus mode", "Typewriter mode", reimplementar) · 🧭 iA Writer/Typora | Medio | M | editor; AST ayuda a delimitar el bloque activo |
| F9 | **Soporte TextBundle (import/export)** | Estándar `.textbundle`/`.textpack` que empaqueta el `.md` con sus imágenes. | 🗳️ #1340 · 🧭 interoperabilidad (Ulysses, Bear, Marked) | Medio | M | FS; complementa Q5 (pegar imágenes) |
| F10 | **Checkboxes interactivos / indeterminados** | Marcar `- [ ]` desde el preview; soportar estado intermedio `- [-]`. | 🗳️ #1281, #1293 ("复选框好像不能使用" = checkboxes no funcionan) · 🧭 GitHub/Obsidian | Medio | M | **🎯 puente**: clic en preview → `WKScriptMessageHandler` → editar el `sourcepos` de ese checkbox en el texto |
| F11 | **Resaltado de sintaxis en el editor** | Colorear Markdown en el panel de edición (no solo el preview). | 🍴 mfbergmann/macdown-swift ("live editor syntax highlighting") · 🧭 todos los editores modernos | Alto | L | editor; el AST con `sourcepos` permite resaltar por nodo en vez de por regex |

**Nota cmark-gfm:** la migración de motor (🍴 sigge) está en
`experiment/cmark-gfm`. Antes de promover features que dependan del AST a `master`
hay que cerrar la **regresión conocida**: cmark-gfm pierde
`highlight`/`superscript`/`underline`/`quote` respecto a hoedown (ver
`CREDITS.md`). Tratar esa paridad como **prerrequisito** de F1/F10/F11 si se
construyen sobre la rama experimental.

---

## 3. El foso (visión: inline + IA + git)

Esto es lo que diferencia a "MacDown Remix" de los demás forks: nadie en el
ecosistema lo tiene. Es donde el AST con `sourcepos` y el puente
`WKScriptMessageHandler` dejan de ser detalle técnico y pasan a ser **el foso
competitivo**. Orden = de habilitador a culminación.

| # | Mejora | Qué es | Procedencia | Valor | Esfuerzo | Encaje |
|---|---|---|---|---|---|---|
| M1 | **Edición inline por bloques (WYSIWYG por nodo)** | Editar el resultado renderizado directamente, bloque a bloque, mapeando cada edición de vuelta al rango `sourcepos` del Markdown fuente (modelo Typora/CodeMirror-MDX). | 🗳️ #1286 "¿editor visual de texto?" · 🧭 Typora/Obsidian Live Preview (el santo grial) | **Muy alto** | XL | **🎯 ES la razón de ser del AST+`sourcepos`+puente.** Toda la arquitectura actual existe para habilitar esto. |
| M2 | **Acciones de IA contextuales por bloque** | Sobre el bloque/selección: reescribir, resumir, traducir, corregir, "explica esto", continuar. Vía API LLM propia. | 🧭 práctica emergente (Notion AI, Obsidian Copilot, Cursor) | **Muy alto** | L | **🎯 puente** `WKScriptMessageHandler` + `sourcepos` para acotar el bloque objetivo y aplicar el diff |
| M3 | **Asistente conversacional sobre el documento** | Chat lateral con el contenido como contexto: "resume esta sección", "genera una tabla de X". Inserta/edita por `sourcepos`. | 🧭 Cursor/Obsidian Copilot | Alto | L | puente + API LLM; reusa la infra de M2 |
| M4 | **Integración git nativa** | Estado del fichero, diff de la sesión, stage/commit desde la app; historial por documento. | 🧭 VS Code, Obsidian Git (plugin de los más instalados) · 🗳️ #735 (MacDown rompe el hard-link al guardar — relevante para integraciones de fichero) | Alto | L | encaja con "modo carpeta/proyecto" (F5) |
| M5 | **Integración Claude Code** | Puente con Claude Code/agentes para tareas sobre el repo de documentación desde el editor. | 🧭 visión del proyecto (`MEMORY.md`) | Alto | XL | depende de M2–M4 maduros |
| M6 | **Diff/aceptación de cambios de IA por bloque** | Mostrar las propuestas de IA como diff inline y aceptar/rechazar por bloque (estilo "Apply"). | 🧭 Cursor/GitHub Copilot Workspace | Alto | L | `sourcepos` para aplicar el patch al rango exacto; reusa M1+M2 |

**Dependencias del foso:** `sourcepos` fiable → **M1** (mapeo edición↔fuente) es el
cimiento; **M2** puede entregarse antes (no exige WYSIWYG, solo selección + puente)
y es el mayor "wow" con menor esfuerzo del bloque. **M4/M5** dependen de tener
modelo de proyecto (F5) y la infra de IA (M2/M3).

---

## 4. Recomendación: los 5 primeros tras la 1.0-beta

Criterio: cerrar credibilidad como editor "vivo y completo" (quick wins muy
demandados) **mientras** se coloca la primera piedra del foso que nadie más tiene.

1. **Q6 — Arreglar "Open Recent" (entradas null).**
   _Es el issue más comentado del proyecto (#1334, 16 comentarios) y un bug de
   primera impresión; barato y de alta visibilidad: dice "este fork sí se
   mantiene"._

2. **Q5 — Pegar/arrastrar imagen como enlace de fichero (#1295).**
   _Carencia que sorprende a todo el que viene de cualquier editor moderno; alto
   valor diario y esfuerzo contenido. Habilita además TextBundle (F9)._

3. **F1 — Outline/TOC navegable en sidebar (#62, #1042).**
   _Primer entregable que **explota el AST con `sourcepos`**: navegación fiable
   imposible de hacer bien con regex. Demanda histórica y base de UI (sidebar)
   reutilizable por Browse mode (F5) y Command Palette (F7)._

4. **F2 — Find & Replace con regex (#1123, #707).**
   _Funcionalidad de editor "de mesa" que falta y que la gente echa en falta a
   diario; corrige además el bug de "solo reemplaza la selección". Esfuerzo medio,
   valor alto, sin dependencias._

5. **M2 — Acciones de IA contextuales por bloque.**
   _La pieza del foso con mejor relación impacto/esfuerzo: no necesita WYSIWYG,
   solo selección + el puente `WKScriptMessageHandler` ya existente + `sourcepos`
   para acotar el bloque. Es lo que ningún otro fork tiene y materializa la visión
   antes de acometer la edición inline (M1, XL)._

> **Regla transversal:** ningún ítem se da por "hecho" sin verificar que arranca y
> funciona de verdad en macOS actual (CI = fuente de verdad del build). Y antes de
> construir F1/F10/F11/M1 sobre la rama `experiment/cmark-gfm`, cerrar la paridad de
> extensiones perdidas (highlight/superscript/underline/quote).

---

## Apéndice A — Mapa fork → feature (para cherry-pick / inspiración)

| Fork | Aporta | Tratamiento |
|---|---|---|
| `plateaukao` (base) | Mermaid v11, default-layout pref, bordes de tabla en temas | ya en base |
| `RezaAmbler/macdown_arm` | Font zoom, Light/Dark/Sepia, TOC links, fix crash toolbar | **integrado** (`CREDITS.md`) |
| `treehousetim` | Auto-reload (**integrado**), **Quick Look extension** (Q12), reload, release.sh | Q1 hecho; Q12 pendiente (target nuevo) |
| `nyimbi` | **Export DOCX/PPTX** + presets + portadas | candidata → F3 (épica) |
| `SiggeMcKvack` | **cmark-gfm**, Sparkle 2, GitHub Dark / GitLab themes | cmark en `experiment/cmark-gfm`; temas → Q8 |
| `xhu96` | Apple Silicon + macOS 11, localización albanesa | build cubierto; l10n aparte |
| `duro` | Tamaño de ventana preferido, preview-only | candidata (entrelazada, adaptar) |
| `Wirtzer/Markly` 🔒 | Focus/Typewriter, WikiLinks, Command Palette, sidebar+tabs, view modes, writing stats, filler-word highlight | **solo inspiración — reimplementar** (F6, F7, F8, F10, Q10) |
| `mfbergmann/macdown-swift` | Live syntax highlight en editor, port Swift | inspiración → F11; el port diverge |

## Apéndice B — Issues citados (todos de `MacDownApp/macdown`)

Calidad/bugs: #1334 (Open Recent null, 16 comments), #1356, #1330, #1343,
#1341, #707, #735. — Quick wins: #1324 (strike), #1304 (zoom), #1311 (img scale),
#1350/#1136/#1196 (code wrap/PDF), #1295 (paste image), #1278 (text replacements),
#1366 (Quick Look, 9 comments), #1279 (list continuation), #370/#436/#1239/#1031/#812
(word count), #1307/#1300 (themes/CSS). — Features grandes: #62/#1042 (outline/TOC),
#1123/#560 (find&replace regex), #1291/#1299 (PDF), #1336/#1358 (folder/browse mode),
#1340 (TextBundle), #1281/#1293 (checkboxes). — Visión: #1286 (editor visual),
#735 (hard-link al guardar). — Estado del proyecto: #1335, #1357, #1348, #1283.
