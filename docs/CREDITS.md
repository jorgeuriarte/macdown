# Créditos de features integradas

Este fork incorpora trabajo de otros forks de la comunidad MacDown. Cada feature
conserva la **autoría original en el histórico de git** (el autor del commit es la
persona que lo escribió; nosotros figuramos solo como *committer*). Esta tabla
documenta la procedencia de forma explícita.

El proyecto base es [`plateaukao/macdown`](https://github.com/plateaukao/macdown),
a su vez fork de [`MacDownApp/macdown`](https://github.com/MacDownApp/macdown)
(MIT, Tzu-ping Chung y colaboradores).

| Feature | Autor | Fork de origen | Commits |
|---|---|---|---|
| Font zoom + modos de vista Light/Dark/Sepia, enlaces de TOC internos, fix de crash en grupos de toolbar segmentados | **Reza Ambler** | [RezaAmbler/macdown_arm](https://github.com/RezaAmbler/macdown_arm) | `beb1bac`, `9d27a8f`, `395fba0`, `dc10f46` |
| Recarga automática del documento cuando el fichero cambia en disco | **Tim** (treehousetim) | [treehousetim/macdown](https://github.com/treehousetim/macdown) | `1b42ba3` |

> Cómo se integran: una rama `feature/*` por feature, `git cherry-pick -x`
> (preserva autor y referencia al commit original), resolución de conflictos
> documentada en el mensaje de commit, y validación de build en CI vía Pull
> Request antes de integrar a `master`.

## Candidatas pendientes (mapeadas, aún no integradas)

Estas features tienen valor pero requieren más que un cherry-pick (re-implementación,
desenredo de cambios entrelazados, o decisión por su tamaño/riesgo). Se documentan
aquí para no perderlas y respetar su atribución desde ya.

| Feature | Autor | Fork | Estado / motivo |
|---|---|---|---|
| Tamaño de ventana preferido | Adam Duro | [duro/macdown](https://github.com/duro/macdown) | Entrelazada con su modo *preview-only*, que solapa con el que ya trae plateaukao. Requiere adaptación manual. |
| Export DOCX / PPTX, presets y portadas | Nyimbi Odero | [nyimbi/macdown](https://github.com/nyimbi/macdown) | Alto valor; 12 commits con archivos nuevos (`MPOfficeExporter`, `MPExportOptions`). Integración grande: abordar como épica propia. |
| Quick Look Preview Extension (.md en Finder) | Tim (treehousetim) | [treehousetim/macdown](https://github.com/treehousetim/macdown) | Añade un *target* nuevo al `.xcodeproj`; no cherry-pickea limpio, requiere recrear el target. |
| cmark-gfm (reemplazo de hoedown) | Carl | [SiggeMcKvack/macdown](https://github.com/SiggeMcKvack/macdown) | **Integrada en la rama `experiment/cmark-gfm`** (no en master): compila en CI y publica pre-releases en el canal experimental (p.ej. `v0.9-cmark.1`). Pierde highlight/superscript/underline/quote. |
| Modernización Apple Silicon + localización albanesa | Xhulio Lavdari | [xhu96/macdown](https://github.com/xhu96/macdown) | Parte ya cubierta por nuestro build universal; la localización es aislada y se puede traer aparte. |
