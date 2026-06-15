# Diario de desarrollo — MacDown (fork propio)

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
