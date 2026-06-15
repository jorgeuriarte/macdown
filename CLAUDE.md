# CLAUDE.md — MacDown Remix (fork de mantenimiento propio)

> Instrucciones específicas de este proyecto. Complementan, no sustituyen, las
> instrucciones globales de `~/.claude/CLAUDE.md`.

## 1. Qué es este repositorio

**MacDown Remix** — un **fork de mantenimiento propio de
[MacDown](https://github.com/MacDownApp/macdown)**, el editor Markdown para macOS de
Tzu-ping Chung (MIT). El original está **abandonado** (último commit en julio de 2023)
y **no compila ni arranca** en macOS / Apple Silicon modernos.

La idea del proyecto — y de su nombre — es **reunir lo mejor de varios mundos de
MacDown en uno**: tomar la base más sana, traer las mejores aportaciones dispersas por
los forks de la comunidad, y evolucionarlo donde haga falta. Respetando siempre la
**licencia MIT y el copyright originales** y **sin suplantar** al MacDown oficial
(identidad propia, releases propias). La atribución de cada pieza vive en
[`docs/CREDITS.md`](docs/CREDITS.md) y en la ventana propia "Acerca de MacDown Remix".

Objetivos vivos:

- Mantener MacDown **vivo y compilable** en macOS actual (Apple Silicon, Xcode reciente).
- **Reunir y consolidar** las mejores features de los forks, una por una, con build verde.
- Evolucionar la base hacia un **editor moderno** (motor con AST, preview WebKit moderno;
  ver [[vision-editor-moderno]] en memoria).
- Producir **releases instalables** reproducibles.

No es un fork en la "red" de GitHub de MacDownApp: es un **repo independiente** (más
control, Actions sin restricciones, releases propias), pero mantiene como `remotes` el
original y los forks interesantes para hacer cherry-pick.

### Decisión clave (2026-06): colapsar a UNA sola línea — "MacDown Remix"

Tras consolidar features sobre cmark-gfm y validar un spike de WKWebView (render +
scroll-sync bidireccional), se decide **enterrar la doble línea** (estable hoedown /
experimental cmark-gfm) y converger en **una única línea: cmark-gfm + WKWebView**, que
pasa a ser *el* MacDown Remix.

- **Identidad:** nombre **"MacDown Remix"**, bundle id **`net.omelas.macdown-remix`**
  (no choca con el MacDown estable `net.omelas.macdown`).
- **Coste asumido:** se pierden 3 extensiones de hoedown (resaltado `==`, superíndice
  `^`, subrayado `_`). A cambio: AST con `sourcepos` (habilita la edición inline + IA) y
  WebView moderno.
- La línea **hoedown + WebView legacy** se **archiva** como tag de referencia
  (`legacy-hoedown`), no se borra.

## 2. Objetivos (en orden de prioridad)

1. **Build verde en CI** que produzca un `.app` que arranca en macOS actual.
2. **Saneamiento mínimo**: fix del crash de arranque, arm64, deployment target.
3. **Features incrementales** por cherry-pick, una por rama, con build tras cada una.
4. **Releases** con tag, binario y (a futuro) auto-update Sparkle.
5. **Tracking continuo** del ecosistema de forks para no perdernos mejoras nuevas.

## 3. Aproximación / decisiones de arquitectura

| Decisión | Elección | Por qué |
|---|---|---|
| Base de partida | **`plateaukao/macdown`** | El fork activo más reciente que conserva la arquitectura Objective-C original → cherry-picks limpios. Trae Mermaid v11 y mejoras de layout. |
| **Motor de render** | **`cmark-gfm`** (CommonMark + GFM) | AST con `sourcepos` por bloque → habilita la visión inline + IA. Integrado desde `SiggeMcKvack`. Coste: pierde 3 extensiones de hoedown. |
| **Preview** | **WKWebView** (migración en curso) | El WebView legacy está deprecado (macOS 10.14) y usa APIs privadas. WKWebView = bridge JS↔ObjC moderno (`WKScriptMessageHandler`), base de la edición inline. Spike validado. |
| Modelo de repo | **Independiente (mirror)**, no fork en la red | Actions completas, releases sin ruido. El upstream está muerto. |
| Entorno de build canónico | **GitHub Actions** | El entorno local (macOS 26.x / Xcode 26.x) es demasiado nuevo. CI fija una combinación reproducible. Builds de rama suben artefacto descargable. |
| Integración de features | **Cherry-pick selectivo** desde remotes (con `-x`, preservando autoría) | Control total; evita arrastrar rebrands o cambios de licencia. |

⚠️ **No cambiar estas decisiones sin consenso** (ver instrucciones globales). El motor
(cmark-gfm) y el preview (WKWebView) ya están **decididos y validados**; lo que queda es
terminar la migración WK a producción (scheme handler, word-count desde el markdown,
copy-HTML, impresión, zoom con `magnification`, callback de MathJax).

## 4. Modelo de git

**Remotes** (configurados en local; regénralos con los comandos de abajo si clonas de nuevo):

```
origin      → este repo (nuestro)
upstream    → MacDownApp/macdown        (original, congelado — referencia histórica)
plateaukao  → plateaukao/macdown        (nuestra base)
sigge       → SiggeMcKvack/macdown      (cmark-gfm, Sparkle 2, temas)
nyimbi      → nyimbi/macdown            (export DOCX/PPTX)
treehouse   → treehousetim/macdown      (Quick Look extension)
reza        → RezaAmbler/macdown_arm    (zoom, view modes, TOC, auto-update)
xhu96       → xhu96/macdown             (universal arm64+Intel, Sparkle 2)
duro        → duro/macdown              (preview-only, tamaño de ventana)
markly      → Wirtzer/Markly            (rebrand cerrado — SOLO inspiración, no mergear)
swift       → mfbergmann/macdown-swift  (port a Swift — referencia, diverge)
```

Recrear los remotes (si hiciera falta):

```bash
git remote add upstream  https://github.com/MacDownApp/macdown.git
git remote add plateaukao https://github.com/plateaukao/macdown.git
git remote add sigge     https://github.com/SiggeMcKvack/macdown.git
git remote add nyimbi    https://github.com/nyimbi/macdown.git
git remote add treehouse https://github.com/treehousetim/macdown.git
git remote add reza      https://github.com/RezaAmbler/macdown_arm.git
git remote add xhu96     https://github.com/xhu96/macdown.git
git remote add duro      https://github.com/duro/macdown.git
git remote add markly    https://github.com/Wirtzer/Markly.git
git remote add swift     https://github.com/mfbergmann/macdown-swift.git
```

**Ramas**: `master` es la línea estable (igual nombre que la base y los forks →
comparaciones y cherry-picks naturales). Cada mejora va en su propia rama
`feature/...` y se integra a `master` con build verde (ver instrucciones globales
sobre branch-before-code).

**Flujo de integración de una feature de otro fork:**

```bash
git fetch reza
git log master..reza/master --oneline        # ver qué trae
git checkout -b feature/font-zoom master
git cherry-pick <sha>...<sha>                 # o merge --no-ff selectivo
# build en CI (push) o local; resolver conflictos; validar que arranca
git checkout master && git merge --no-ff feature/font-zoom
```

## 5. Cómo se construye

MacDown usa **CocoaPods** (no SwiftPM) y un **workspace**:

```bash
pod install                       # genera/actualiza MacDown.xcworkspace
xcodebuild -workspace MacDown.xcworkspace -scheme MacDown -configuration Release
```

- Dependencias clave (Podfile): `hoedown` (render), `Sparkle` (auto-update, v1.x),
  `handlebars-objc`, `MASPreferences`, `PAPreferences`, `JJPluralForm`, etc.
  Algunas vienen de un spec repo propio: `MacDownApp/cocoapods-specs`.
- Submódulo: `Dependency/prism` (resaltado de sintaxis en el preview).
- El **entorno de build canónico es GitHub Actions** (ver `.github/workflows/`).
  El build local en macOS muy reciente puede fallar por el deployment target
  histórico; usa CI como fuente de verdad.

## 6. Tracking del ecosistema de forks  ⭐

Mantener viva la información de qué hay en cada fork y **detectar nuevos** (tanto del
MacDown original como de las líneas evolucionadas) es parte del proyecto: el valor de
"MacDown Remix" es ir recogiendo lo mejor que aparezca por ahí.

**🔁 Rutina periódica (hazla de vez en cuando, p. ej. al empezar un ciclo de trabajo,
o si el usuario pregunta "¿qué hay de nuevo por los forks?"):**

```bash
./claude_tools/track_forks.sh            # rastrea y reescribe docs/FORKS.md + snapshot
./claude_tools/track_forks.sh --dry-run  # solo resumen, no escribe
```

Tras ejecutarlo, **revisa la sección de NOVEDADES** al principio de
[`docs/FORKS.md`](docs/FORKS.md) (forks nuevos y forks con commits nuevos desde el último
snapshot) y resume al usuario lo que merezca la pena mirar/traer. Si algo interesa, se
integra por cherry-pick con atribución (ver §4) y se anota en `docs/CREDITS.md`.

Cómo funciona:

- Lee los **repos semilla** de [`claude_tools/seeds.txt`](claude_tools/seeds.txt):
  el original **y** los forks evolucionados/migrados (Markly, macdown-swift, …).
- Para cada seed lista sus forks, descarta los muertos (filtro por fecha de push)
  y compara los activos para quedarse con los que tienen **commits propios**.
- Escribe el informe legible en [`docs/FORKS.md`](docs/FORKS.md) y un snapshot en
  `claude_tools/forks_state.json`.
- En cada ejecución compara contra el snapshot anterior y destaca las
  **novedades** (forks nuevos y forks con commits nuevos) al principio del informe.

Para empezar a vigilar una nueva línea evolucionada, **añade su `owner/repo` a
`seeds.txt`** y vuelve a ejecutar. Si una línea migrada (p. ej. el port a Swift)
gana tracción, sus propios forks aparecerán automáticamente.

> Idea de automatización (no implementada aún): un workflow programado semanal que
> ejecute el tracker y abra un issue/PR si `forks_state.json` cambia.

## 7. Estructura del repo

```
MacDown.xcworkspace / .xcodeproj   proyecto Xcode
MacDown/                           código de la app (Objective-C)
MacDownTests/                      tests
macdown-cmd/                       CLI auxiliar
Tools/                             generadores de estilos, scripts de build
Dependency/prism/                  submódulo (syntax highlight del preview)
Podfile / Podfile.lock             dependencias CocoaPods
.github/workflows/                 CI: build, release, tagging
claude_tools/                      utilidades de mantenimiento (tracking de forks)
docs/                              documentación (FORKS.md, DIARY.md, …)
DOCS.md                            índice de documentación
```

## 8. Estado conocido / gotchas

- **Crash de arranque**: out-of-bounds en `MPToolbarController
  toolbarDefaultItemIdentifiers:` en macOS moderno. Es EL fix transversal que
  aplican casi todos los forks vivos. Verificar que nuestra base lo tiene o
  portarlo (está en sigge, treehouse, shingu-m, djpadz, alicela1n, …).
- **Apple Silicon**: subir deployment target y compilar arm64 (referencia:
  `xhu96`, `David-Talaga`, `tikkal`, `djpadz`).
- **Sparkle**: la base usa 1.x; varios forks migran a Sparkle 2.x (`sigge`, `xhu96`).
- **Local muy nuevo**: el entorno de desarrollo es macOS 26.x / Xcode 26.x; trata
  CI como la verdad para el build.

## 9. Convenciones

Aplican las globales de `~/.claude/CLAUDE.md`: feature-branch antes de codear,
commits frecuentes, build antes de push, documentos en `/docs` referenciados desde
`DOCS.md`, diario en `docs/DIARY.md`, y honestidad sobre el estado real (nada de
"funciona al 100 %" sin haberlo verificado de verdad).
