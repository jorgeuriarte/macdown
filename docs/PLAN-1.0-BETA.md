# Plan hacia MacDown Remix 1.0-beta

> Objetivo de release. Cada paso, su build en CI con binario descargable para probar.
> Ver también [`PLAN-CONSOLIDACION.md`](PLAN-CONSOLIDACION.md) (pasos 1-5, ✅) y
> [`WKWEBVIEW-MIGRATION.md`](WKWEBVIEW-MIGRATION.md).

## 🎯 GOAL — MacDown Remix 1.0-beta

Una **pre-release `v1.0-beta.1`** en `master`, **línea única** (cmark-gfm + WKWebView por
defecto), donde el **flujo diario funciona de punta a punta**: editar, preview (tema,
tablas, task lists, footnotes, mermaid, prism), scroll-sync bidireccional, **imprimir /
exportar PDF**, **zoom del preview**, **contador de palabras** y **MathJax** — todo
coherente en modo WK. Publicada como pre-release **firmada (EdDSA)** en el canal Remix
(`appcast-remix.xml`), con la línea hoedown legacy **archivada** (`legacy-hoedown`).

**Fuera de alcance (para 1.0 final, tras "secarse"):** `WKURLSchemeHandler` (sustituir el
HTML temporal), **notarización / Developer ID** (auto-update completo) y pulido a partir
del uso real.

## Por qué 1.0-beta y no 1.0

El spike WKWebView validó render + scroll-sync, pero la migración no está cerrada: varias
piezas leen aún del WebView legacy (vacío en modo WK). Hasta cerrarlas, no es "todo
funciona". 1.0-beta marca el hito de forma honesta.

## Fases

### Fase A — Cerrar los gaps funcionales de WKWebView
Que el modo WK (por defecto) sea coherente. Cada uno con su build.

| # | Gap | Plan | Estado |
|---|---|---|---|
| A1 | **Contador de palabras** | Contar desde el **markdown del editor** (ya en memoria), no del DOM. Elimina la dependencia de `DOMNode+Text`. Funciona en ambos motores. | ⏳ |
| A2 | **Zoom del preview** | Usar `magnification` de WKWebView (o `zoom` CSS vía JS) en vez de `setPageSizeMultiplier` (API privada del legacy). | ⏳ |
| A3 | **Imprimir / exportar PDF** | Portar a WKWebView (`createPDFWithConfiguration:` / operación de impresión de WKWebView) en vez del `WebFrameView` del legacy. | ⏳ |
| A4 | **Callback de MathJax** | Cablear vía el `WKScriptMessageHandler` que ya existe (mensaje "math done") en vez del `windowScriptObject` legacy. | ⏳ |

### Fase B — Línea única
| # | Paso | Estado |
|---|---|---|
| B1 | Merge `experiment/wkwebview` → `master` (Remix pasa a ser la línea principal). | ⏳ |
| B2 | Archivar la línea hoedown + WebView legacy como tag `legacy-hoedown`. | ⏳ |

### Fase C — Canal de release de Remix
| # | Paso | Estado |
|---|---|---|
| C1 | Workflow de release para Remix: tags `v1.0-beta.N` → pre-release + `appcast-remix.xml` firmado (EdDSA). | ⏳ |
| C2 | Actualizar `install-latest-beta.sh` para el canal Remix. | ⏳ |
| C3 | **Tag `v1.0-beta.1`** → primera pre-release oficial de MacDown Remix. | ⏳ |

## Tras 1.0-beta (no en este goal)
- `WKURLSchemeHandler` (quita el HTML temporal en disco; arregla imágenes relativas).
- Notarización + Developer ID → auto-update que instala de verdad.
- Pulido según el uso diario → **1.0 final** cuando se haya "secado".
