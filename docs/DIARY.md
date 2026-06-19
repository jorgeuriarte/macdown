# Diario de desarrollo — MacDown (fork propio)

## 2026-06-19 — Edición inline M1: decisión del gap + inspector del visor

### Qué se hizo
- **Decisión del gap AST↔secciones** (`docs/EDICION-INLINE.md` §7): cmark da hermanos
  planos sin `<section>`. Se elige **Opción D** (calcular las secciones **al vuelo en JS**
  desde los headings + `data-sourcepos`, render de cmark **intacto**) para M1; **B-JS**
  (envolver `<section>` tras cargar) como evolución cuando hagan falta cajas reales;
  **B-ObjC** sólo para export. A y B-pura descartadas. Prototipo `prototypes/secciones.html`.
- **Inspector del visor portado al DOM real** (rama `feature/inline-edit-mvp`):
  `Resources/Extensions/inline-inspector.js`. A diferencia del prototipo (que usaba
  `<section>`/`data-kind`/`data-md` falsos), aquí deriva el tipo del `tagName` y el rango
  de `data-sourcepos`, y construye las **Secciones como niveles virtuales** (Opción D).
  Reaprovecha el puente: postea `block`/`selection` (recuadro/cursor en el editor) y
  redefine `macdownHighlightLines` (editor→visor), sustituyendo a la selección conectada
  clásica **mientras vive en la rama**.
- Empaquetado **sin tocar el `.pbxproj`**: el `.js` cae en la folder-reference
  `Resources/Extensions` (que se copia íntegra). CI construye también `feature/**`.
- Se descartó el flag de preferencia (la **rama ya es el aislamiento**, apunte del usuario):
  el inspector va siempre activo en la rama; una preferencia real llegará al ir hacia master.

### Verificación (de verdad)
- Build CI verde (build 119) → el ObjC compila. `.app` instalada en `/Applications`,
  arranca sin crash, `inline-inspector.js` empaquetado.
- **Validado en el visor real por el usuario** ("funciona, sí"): franja, hover, fijar,
  reflejo en el editor y, lo clave, el **salto a nivel Sección** (recuadro que abarca toda
  la sección H2+contenido, inexistente en el HTML) — la Opción D funciona sobre DOM plano.
- Harness de navegador `/tmp/inspector-harness.html` (DOM plano imitando cmark) para iterar
  la interacción sin recompilar.

### Pendiente (siguiente sub-hito)
- **Edición real del fuente**: ✏︎/doble-clic → mini-editor con el Markdown del bloque →
  reescribir el rango exacto vía `sourcepos` + re-render. Ahora sólo destella.
- Preferencia real (con UI) al converger hacia master; re-render fino; ediciones que
  cambian la estructura.

## 2026-06-19 — Estilo del recuadro de bloque (esquinas + dash + temas)

### Qué se hizo
- El recuadro de la selección conectada pasa de un outline simple a **cuatro esquinas**
  (30px) + **trazo central por lado** en bloques de **≥10 líneas**. El diseño se eligió
  iterando con maquetas HTML (galerías abiertas en el navegador) en lugar de recompilar
  por cada variante — mucho más rápido para decisiones visuales.
- **Integración con los temas, cada panel con el suyo**: el **editor** usa el `caret` del
  `.style` (`insertionPointColor`); el **visor** usa el acento del CSS (color de enlace)
  leído en runtime. Así el recuadro se siente nativo en cada lado.
- **Aire interior sin reflow**: el visor con `::after` e `inset:-6px`; el editor con un
  inset del recuadro clampado al **área del text container** (las verticales se perdían
  porque el NSTextView recorta el dibujo al margen — diagnosticado con instrumentación a
  fichero). Merge en `bc81e91`.

### Pendiente
- Hacer el estilo del recuadro configurable (preferencia de estilo).
- El dash de ≥10 líneas está implementado pero apenas probado en vivo (los bloques de
  prueba se quedan en el umbral); revisar si conviene bajarlo.

## 2026-06-18 — Buscador en el visor + selección conectada por bloque

### Qué se hizo
- **Buscador en el visor (⌘F)**: WKWebView no trae find bar; se añade uno propio
  (campo + ‹/›/✕, Enter busca, Esc cierra) sobre `findString:withConfiguration:`
  (macOS 11+). Una subclase `MPWKWebView` captura `performFindPanelAction:` y lo
  reenvía al documento, para que el ⌘F llegue al visor cuando tiene el foco (antes lo
  interceptaban el editor o WebKit). El find del editor (NSTextView) sigue intacto.
- **Selección conectada editor↔visor por bloque**: se activa `CMARK_OPT_SOURCEPOS`
  (cada elemento HTML lleva `data-sourcepos="L:C-L:C"`). Mover el cursor en el editor
  recuadra el bloque equivalente en el visor; clicar en el visor recuadra el bloque y
  lleva el cursor allí. El recuadro es un **outline fino** en AMBOS lados (visor por
  CSS, editor por `drawRect` en `MPEditorView`), no un fondo: la selección de texto
  queda **reservada** para una futura sincronización de selección real. Anti-bucle por
  timestamp. Es el primer peldaño de la visión de edición inline. Merge en `e212b39`.

### Decisiones
- El ⌘F es contextual al panel con foco (estándar); en el visor requiere clic previo.
- Mapeo por **bloque** (lo que da `sourcepos`), no por carácter; el desfase de líneas
  por math display multilínea es un caso borde aceptado.

### Pendiente
- Sincronización de selección real (carácter/palabra) — usaría el aspecto "seleccionado".
- Contador "X de Y" en el buscador del visor. Retirar el flag/legacy WebView en 1.0.

## 2026-06-16 — Fase B: convergencia en línea única (cmark-gfm + WKWebView)

### Qué se hizo
- **A4 (MathJax) cerrado**: protección de math antes de cmark-gfm (que mangla LaTeX)
  y reinserción tras render. Display `$$..$$`, inline `\(..\)`, con heurística
  anti-monedas (`$5`, `$10`, `$20,000` quedan como texto) y respeto a bloques de
  código. Verificado en pipeline real (el `\\` de salto de fila de la matriz llega
  intacto al HTML; antes era un artefacto de visualización del terminal).
- **Fase B — línea única**: se entierra la doble línea (estable hoedown / experimental
  cmark-gfm). `master` pasa a ser **MacDown Remix** = cmark-gfm + WKWebView.
  - `legacy-hoedown` (tag) archiva la línea hoedown + WebView legacy (`fd7b0ff`).
  - Convergencia hecha como **merge commit con árbol controlado**: el código viene
    íntegro de `experiment/wkwebview` (build 97, verde y validado) y los docs/gestión
    de la línea master (CLAUDE.md, README, planes, ROADMAP, tracking de forks, appcasts).
  - `master` = `9b5c57d`, **build verde** en CI bajo el nuevo workflow
    "Build MacDown Remix (cmark-gfm + WKWebView)".

### Decisiones
- No se hizo `git merge` automático: las dos líneas integraron features por cherry-pick
  (mismo contenido, SHAs distintos) → merge-base antiquísimo y conflictos masivos. Se
  pobló el árbol desde `wkwebview` y se reinyectaron los docs de master, preservando
  ambos padres en el grafo y dejando el código idéntico al build verde.
- Se re-desactivó Dependabot (la convergencia reintrodujo su config desde la línea
  cmark; master lo tenía desactivado a propósito). Sus 2 PRs se cerraron.

### Instalación local y CLI tool
- Instalado el build de master como **MacDown Remix** (única app MacDown del sistema);
  borrada la beta `MacDown cmark-gfm.app` y desinstalada la estable hoedown vía
  `brew uninstall --cask macdown` (el cask oficial 0.7.2 estaba deprecated).
- **CLI `macdown` autónomo**: el rebrand había dejado `kMPApplicationBundleIdentifier`
  con el id histórico `com.uranusjr.macdown`, así que el helper de CLI no encontraba la
  app; ahora apunta a `net.omelas.macdown-remix`. Y `installShellUtility` escribía
  hardcodeado en `/usr/local/bin` (root, sin privilegios → fallaba en Apple Silicon);
  ahora instala en el prefijo de Homebrew (`/opt/homebrew/bin`, escribible y en PATH),
  igual que la detección. El suite de NSUserDefaults se mantiene (rendezvous + prefs).
- Limpiada una copia rota `~/Dropbox/.../Downloads/_Revisar/MacDown.app` (Info.plist
  ilegible) que LaunchServices resolvía con `open -a MacDown` → error -10810. Hábito
  nuevo: lanzar con `macdown` o `open -b net.omelas.macdown-remix`.

### Auditoría de preferencias y features recuperadas
- Auditoría de los 5 panes de preferencias (2 subagentes Explore): todos los controles
  conectados, sin huérfanos; el pane Markdown solo expone extensiones que cmark-gfm
  soporta (no quedaron toggles muertos de hoedown). El flag `experimentalWKWebView`
  (default ON, sin UI) se mantiene como red de seguridad de la WebView legacy hasta
  cerrar la migración WK. El typo `extensionStrikethough` se deja a propósito (6 archivos
  + migración de prefs para un nombre interno invisible: riesgo > beneficio).
- Features recuperadas (perdidas en la convergencia, no portadas de hoedown a cmark):
  - **⌘L** para rotar el modo de vista (la convergencia lo había dejado en ⌃⌘0).
  - **Resaltado `==x==` → `<mark>` y superíndice `^x^` → `<sup>`** vía postproceso del
    markdown (cmark va con UNSAFE), respetando bloques y spans de código. 9 casos en test.
  - **Navegación de enlaces en WKWebView**: un clic en un enlace a otro `.md` lo abría
    como texto plano; se portó el `WebPolicyDelegate` legacy a un `WKNavigationDelegate`
    que abre el documento en MacDown (ventana nueva, coherente con el modelo
    editor+preview) y deja pasar los saltos a anclas. Merge a master en `78d38bf`.

### Fase C — release v1.0-beta.1 publicada
- Canal de release propio: el workflow publica, en tags `v*-*`, una pre-release
  "MacDown Remix vX" + genera `appcast-remix.xml` firmado con EdDSA (antes apuntaba al
  `appcast-beta` experimental). El Info.plist ya apuntaba al canal Remix (`SUFeedURL`).
  `install-latest-beta.sh` apunta al canal Remix y a `MacDown Remix.app`.
- **Tag `v1.0-beta.1`** → pre-release publicada (build 106, `.zip`+`.dmg`), appcast firmado
  y commiteado a master. Validado end-to-end con `install-latest-beta.sh` (descarga e
  instala la 1.0-beta.1 desde el canal Remix).

### Pendiente (hacia 1.0 final)
- Notarización / Developer ID: sin ella el auto-update de Sparkle descarga pero no instala
  (hoy se instala a mano con el script). Es el bloqueo real para el auto-update completo.
- `WKURLSchemeHandler` (sustituir el HTML temporal del preview). Pulido cosmético de prefs
  (typo `extensionStrikethough`, UI "Accessory") y eventual retirada del flag/legacy WebView.

## 2026-06-13 — Arranque del fork de mantenimiento

### Qué se hizo
- Análisis del ecosistema: 1146 forks de `MacDownApp/macdown`, 52 con actividad
  posterior al upstream, **32 con commits propios**.
- Decisión de base: **`plateaukao/macdown`** (activo, arquitectura ObjC original).
- Decisión de repo: **independiente (mirror)**, con remotes a upstream y forks clave.
- Clonada la base en local y configurados 10 remotes.
- Escrito el tracker de forks (`claude_tools/track_forks.py` + `.sh` + `seeds.txt`),
  que detecta forks con commits propios y novedades entre ejecuciones.
- Generado el informe inicial [`docs/FORKS.md`](FORKS.md) (baseline).
- Escrito `CLAUDE.md` del proyecto.

### Decisiones tomadas
- Build canónico en **GitHub Actions** (el entorno local macOS 26.x / Xcode 26.x es
  demasiado nuevo para el deployment target histórico).
- `markly` y `swift` quedan como **referencia, no mergeables** (rebrand cerrado /
  port divergente a Swift).

### Aprendizajes
- El fix transversal que aplican casi todos los forks vivos es el crash de arranque
  por out-of-bounds en `MPToolbarController toolbarDefaultItemIdentifiers:`.
- El segundo patrón universal es Apple Silicon (arm64) + subir deployment target.

### Resultados (misma sesión)
- Repo creado: **github.com/jorgeuriarte/macdown** (privado) y push de `master`.
- Workflow `.github/workflows/build.yml`: build universal (arm64+x86_64) sin firma
  en `macos-14`, genera el parser PEG, `pod install`, empaqueta ZIP+DMG.
  **Build verde a la primera.**
- Pipeline de release/tagging probado: tag **v0.8.1** → release publicada con
  `MacDown.dmg` + `MacDown.zip`, versión inyectada desde el tag (0.8.1, build 4).
- Smoke test del binario publicado: proceso vivo 7s sin crash report → **no
  reproduce el crash de arranque del toolbar**.

### Pendiente / salvedades honestas
- **Sin firma ni notarización**: Gatekeeper bloqueará la app (abrir con clic
  derecho → Abrir, o `xattr -dr com.apple.quarantine MacDown.app`). Firma con
  Developer ID = mejora futura (requiere certificado).
- **Verificación visual completa**: falta abrir la app en un Mac y usarla de
  verdad (el entorno de desarrollo es headless con Xcode roto).
- **Dependabot heredado** de plateaukao genera PRs/runs de ruido: decidir si
  desactivarlo o acotarlo.
- El versionado correcto solo se inyecta en releases (tags); los builds de
  `master` muestran 0.1.

### Integración de features (misma sesión)
- **Dependabot heredado desactivado** y su PR cerrado.
- Mapa completo de features candidatas con autoría (ver `docs/CREDITS.md`).
- Features **integradas** (rama `feature/*` → PR → CI verde → merge, autoría preservada):
  1. Font zoom + modos Light/Dark/Sepia + TOC interno + fix toolbar — **Reza Ambler**
     (`RezaAmbler/macdown_arm`), 4 commits. Conflictos resueltos en `MPToolbarController.m`
     (bounds-guard) y `MPDocument.m`.
  2. Recarga automática al cambiar el fichero en disco — **Tim** (`treehousetim/macdown`), 1 commit.
- **Release v0.8.2** publicada con ambas features (DMG+ZIP, universal).
- Feature de *tamaño de ventana preferido* (duro) **descartada por ahora**: entrelazada
  con su preview-only, que solapa con plateaukao → requiere re-implementación.

### Auto-update y más features (misma sesión)
- **Auto-update Sparkle propio** (v0.8.3): feeds → nuestro repo, claves DSA propias
  (privada en secreto de Actions), appcast firmado y publicado por el CI. Verificado
  end-to-end (firma `Verified OK`). Pendiente: firma Developer ID + primer salto manual.
- **Cambio rápido de modo de vista** (⌃⌘1/2/3 + ciclo ⌃⌘0) — feature propia, en master.
- **Selector de canal de actualización**: ya existía (checkbox `updateIncludesPreReleases`);
  solo se aclaró la etiqueta a "Include experimental (beta) updates".
- **Rama `experiment/cmark-gfm`**: motor cmark-gfm (Carl/sigge), compila en CI, pre-release
  `v0.9-cmark.1` en el canal experimental (firma verificada, arranca). Pierde
  highlight/superscript/underline/quote. No se mergea a master.
- **v0.8.4**: release estable con el cambio rápido de modo + selector aclarado.

### Identidad propia, Sparkle 2 y convivencia (sesión)
- **Identidad propia**: bundle ID `net.omelas.macdown` (estable) y
  `net.omelas.macdown-cmark` (experimental), versión con sufijo `-ju`, atribución
  al linaje en el copyright. Deja de suplantar a `com.uranusjr`.
- **Auto-update arreglado** (el menú salía gris): causa real = Sparkle 2 deshabilita
  updates en apps no notarizadas sin **EdDSA**. Solución: `SPUStandardUpdaterController`
  + claves EdDSA (`SUPublicEDKey`, firma del appcast con `sign_update`). Validado:
  la app localiza la nueva versión (SULastCheckTime + appcast en caché + 38>36).
- **Convivencia**: estable (`MacDown.app`) y experimental (`MacDown cmark-gfm.app`)
  instaladas y corriendo **a la vez**, con bundle IDs distintos. Verificado.
- **Dropdown de layout**: modos de vista directos y selectivos (⌃⌘1/2/3 al lado).
- Gatekeeper: sin notarización (de pago), instalar 1 vez desde /Applications sin
  cuarentena; los auto-updates posteriores ya no disparan Gatekeeper.

### Próximos pasos
- Aplicar Sparkle 2/EdDSA también a la rama experimental (su canal beta).
- Features pendientes en `docs/CREDITS.md` (export DOCX/PPTX de nyimbi, Quick Look de treehouse).
- Firmar/notarizar releases (Developer ID) para evitar el bloqueo de Gatekeeper.

## 2026-06-15 — Consolidación sobre cmark-gfm: paso 3 (modos de vista)

### Qué se hizo
- **Paso 3 del plan de consolidación** portado a `feature/consolidate-on-cmark-gfm`:
  dropdown de layout en la toolbar + cambio rápido de modo de vista
  (⌃⌘1 Editor+Vista, ⌃⌘2 solo Editor, ⌃⌘3 solo Vista, ciclo ⌃⌘0).
- Cherry-picks con atribución (`-x`): `2016de9` (modos directos + ciclo) y
  `2b6b36b` (dropdown selectivo que oculta el modo actual).
- Release experimental **`v0.9-cons.4`** (build 57, arm64): CI verde con tests.

### Decisiones tomadas
- La experimental **no traía el enum `MPDefaultLayout` ni `applyDefaultLayout`**
  (infra de plateaukao). Reimplementé `applyLayoutMode:` autocontenido sobre las
  primitivas que sí existen (`setSplitViewDividerLocation:`, `previousSplitRatio`,
  `editorOnRight`, `editorVisible/previewVisible`). Semántica idéntica a la estable.

### Verificación (no solo "compila")
- CI: `xcodebuild test` + compilación arm64 + DMG/ZIP + pre-release + appcast-beta.
- Runtime (instalada vía `gh`, sin cuarentena): la app arranca, el menú "Ver"
  muestra los 4 ítems, y al ciclar la **geometría del split cambia de verdad**:
  Editor Only `1329px` → Preview Only `1329px` (lado opuesto) → Both `664+664`.

### Hallazgo para el paso 4 (TOC)
- Causa raíz del "índice perdido" confirmada: `MPCmarkGFMToHTML` usa
  `cmark_render_html` crudo, que **emite los headings sin `id`**; la TOC genera
  enlaces `#toc_N` que no tienen destino → navegación muerta. Fix previsto:
  post-proceso que inyecte `id="toc_N"` en orden (como `MPPostProcessCodeBlocks`).

## 2026-06-15 — Consolidación paso 4: anclas de heading en cmark-gfm

### Qué se hizo (`v0.9-cons.8`)
- **Dos sistemas de anclas, paridad con la estable**:
  - Cherry-pick de Reza Ambler (anclas **slug** estilo GitHub + su test
    `MPHeadingAnchorTests.m` + smooth-scroll), agnóstico del motor.
  - **`HTMLByAddingTOCHeadingIDs:`**: inyecta `id="toc_N"` para que el macro
    `[TOC]` resuelva (cmark-gfm no emitía `id`). Numeración alineada con el
    generador de TOC.
- **Fix de mojibake** en el texto del macro `[TOC]`: se construía con `%s`
  (UTF-8 leído como Mac Roman → `Instalación`→`Instalaci√≥n`). Decodificado con
  `stringWithUTF8String:`.
- **Plegado de acentos** en el slug (decisión de UX del usuario): `Instalación`
  → `#instalacion`, `Año`→`ano`, ñ→n. **Diverge a propósito de GitHub/hoedown**
  (que conservan acentos) para que los anclas se escriban a mano sin diacríticos.

### Decisiones
- Dos sistemas de anclas en vez de uno: `toc_N` posicional (macro `[TOC]`, sin
  riesgo de matching) + slug aditivo (enlaces a mano). Igual que la estable.
- Stub de test `MPAnchorStubDelegate` completado con los 6 métodos extra que
  exige `MPRendererDelegate` en la línea cmark-gfm (crasheaba con
  `unrecognized selector rendererCmarkExtensions:`).

### Verificación (de verdad, no solo "compila")
- CI verde con tests nuevos: plegado, mojibake (regresión), `toc_N`, pipeline.
- Runtime sobre `prueba-toc.md` (Copy HTML): cada `href` casa con su `id`
  (`#instalacion`↔`id="instalacion"`), el contraejemplo con tilde no casa, y
  el texto del `[TOC]` sale con acentos correctos (0 ocurrencias de `√`).
- Camino de baches honesto: cons.5 falló (stub incompleto), cons.7 arregló el
  mojibake, cons.8 añadió el plegado. Un `gh run watch` dio un falso "exit 0"
  enmascarado por un comando posterior → ahora se captura la conclusión real.

### Pendiente
- Paso 5: usar la base de verdad y decidir migración a WKWebView.
- Salvedad: la inyección `toc_N` (regex sobre `<hN>`) cuenta también headings
  HTML crudos, que el generador de TOC (AST) ignora → desalineación en ese caso
  raro. Misma limitación que el inyector de slugs de la estable.
