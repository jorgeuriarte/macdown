# Migración WebView legacy → WKWebView — Evaluación

> Paso 5 de la consolidación. Evaluación de la superficie actual y plan de
> prototipo. **Aún no se ha tocado código de migración**: este documento es la
> base para decidir con datos. Ver [[vision-editor-moderno]] (memoria) — esta
> migración es el sustrato técnico de la edición inline + IA.

## Por qué

El preview de MacDown usa el **WebView legacy** (WebKit clásico), **deprecado en
macOS 10.14** ("No longer supported; please adopt WKWebView"). Genera decenas de
warnings en CI y usa **APIs privadas no App-Store-safe**. Además, la visión futura
(edición inline por bloques + IA) necesita un puente JS↔nativo moderno y robusto;
WKWebView (`WKScriptMessageHandler` + `evaluateJavaScript`) **es** ese sustrato.

## El bloqueo fundamental

WKWebView ejecuta el JavaScript en un **proceso separado y aislado**. Consecuencia:
**no hay acceso síncrono al DOM** desde Objective-C. Todo lo que hoy es síncrono
(leer el DOM, evaluar JS y usar el retorno en la misma línea) pasa a ser
**asíncrono con callbacks**. Eso es el cambio de paradigma, no las llamadas sueltas.

## Superficie actual (mapa)

Ficheros: `MPDocument.m` (casi todo), `DOMNode+Text.m/.h`,
`WebView+WebViewPrivateHeaders.h`, `MPMathJaxListener.m`, `MPDocument.xib`.

| # | Área | API legacy | Equivalente WKWebView | Dificultad |
|---|---|---|---|---|
| 1 | **Scroll sync editor↔preview** | `mainFrame.javaScriptContext evaluateScript:` (síncrono, lee `getBoundingClientRect().top` de los headers) | `evaluateJavaScript:completionHandler:` (async) | 🔴 Alta (UX en vivo) |
| 2 | **Word count** | `DOMNode+Text`: camina el árbol DOM en ObjC (`textCount`) | — | 🔴 Alta (pero *evitable*, ver abajo) |
| 3 | **Callback de MathJax** | `windowScriptObject setValue:` + WebScripting | `WKScriptMessageHandler` + `WKUserContentController` | 🟠 Media |
| 4 | **Zoom del preview** | `setPageSizeMultiplier:` (**API privada**) | `magnification` (pública) o CSS `zoom` | 🟠 Media (más limpio en WK) |
| 5 | **Interceptar MathJax.js** | `WebResourceLoadDelegate` redirige al bundle | `WKURLSchemeHandler` o inyectar el script | 🟠 Media |
| 6 | **Copy HTML (selección)** | `selectedDOMRange.markupString` | async, o usar `currentHtml` ya guardado | 🟠 Media (*parcialmente evitable*) |
| 7 | **Color de fondo del preview** | `getComputedStyle` sobre `<body>` | leer del tema, sin DOM | 🟢 Baja (*evitable*) |
| 8 | **Carga de HTML + recursos locales** | `loadHTMLString:baseURL:` con `file://` | `loadFileURL:allowingReadAccessToURL:` o custom scheme | 🟠 Media (seguridad más estricta) |
| 9 | **Impresión / export PDF** | `WebFrameView printOperationWithPrintInfo:` | `createPDFWithConfiguration:` / `printOperation` | 🟠 Media (API distinta) |
| 10 | **Política de navegación de links** | `WebPolicyDelegate` | `WKNavigationDelegate decidePolicyFor` | 🟢 Baja (mapeo directo) |
| 11 | **Desactivar drag, restaurar scroll** | `WebUIDelegate`, `enclosingScrollView.bounds` | `WKNavigationDelegate` + `scrollView` | 🟢 Baja |

**Recuento**: 1 eval JS síncrona con retorno usado · ~15 accesos directos al DOM ·
5 delegados (7 métodos) · 1 puente JS→ObjC · 2 APIs privadas.

## Lo que se puede *evitar* en vez de portar (clave)

Varias de las piezas "difíciles" no hay que migrarlas, se rediseñan:

- **Word count**: contar desde el **markdown del editor** (que ya tenemos en
  memoria), no del DOM renderizado. Elimina `DOMNode+Text` por completo.
- **Color de fondo** (para el tema de mermaid, etc.): leer del **tema CSS
  seleccionado**, no del DOM computado. (El `mermaid.init.js` ya lo hace en JS.)
- **Copy HTML del documento entero**: usar `currentHtml` (ya se guarda). Solo el
  "copiar selección como HTML" necesita la ruta async.

Con eso, la migración real se reduce a: **scroll-sync async**, **puente MathJax**,
**zoom**, **carga de recursos** e **impresión**.

## El único riesgo que necesita prototipo

El **scroll-sync** es lo único que no se puede juzgar en teoría: ¿se siente con
lag si la posición de los headers se consulta de forma asíncrona durante el scroll
en vivo? Hay que **medirlo**. El resto es mecánico.

## Plan de prototipo (spike) propuesto

Rama `experiment/wkwebview` (no toca la experimental estable). Objetivo: de-riesgar,
no terminar. Con CI + binario descargable como el resto.

1. **Preview WKWebView en paralelo** detrás de un flag (la legacy sigue intacta).
2. **Render + recursos locales**: que cargue el HTML con prism/mermaid/mathjax desde
   el bundle (valida el punto 8, la seguridad de `file://`).
3. **Callback de MathJax** vía `WKScriptMessageHandler` (valida el punto 3).
4. **Scroll-sync async** y **medir la sensación** (valida el punto 1, el riesgo real).

Si el spike va bien → migración completa por piezas, cada una releasable. Si el
scroll-sync se siente mal → se decide con datos (mantener legacy, o async + tweaks).

## Estado

- [x] Evaluación / mapa de superficie (este documento)
- [ ] Spike `experiment/wkwebview` (pendiente de luz verde sobre el enfoque)
- [ ] Decisión: migración completa vs. mantener legacy
