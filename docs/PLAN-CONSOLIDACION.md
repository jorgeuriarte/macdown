# Plan de consolidación sobre cmark-gfm

> Objetivo: **una sola línea funcional** basada en la rama experimental
> (`experiment/cmark-gfm`, motor cmark-gfm con AST — el de futuro), portando las
> features de la estable. Validar por el camino si el WebView legacy aguanta o
> pide migrar a WKWebView. **Antes** de abordar la visión de editor inline+IA.

## Principios
- Trabajo en rama `feature/consolidate-on-cmark-gfm` (desde `experiment/cmark-gfm`).
- **CI + pre-release en cada hito**: cada paso significativo publica una pre-release
  con binario descargable (tags `v0.9-cons.N`) para poder probar de verdad.
- Los **35 tests** corren en cada build (red de seguridad).
- Orden por riesgo creciente: fallar pronto y barato.

## Pasos

| # | Paso | Riesgo | Estado |
|---|---|---|---|
| 1 | Infra de la experimental a la par: Sparkle 2/EdDSA (`SPUStandardUpdaterController` + `SUPublicEDKey` + appcast EdDSA) | Bajo | — |
| 2 | Cherry-picks limpios (no tocan el motor): auto-reload, zoom, modos Light/Dark/Sepia, fix toolbar, **mermaid v11** | Bajo | — |
| 3 | Dropdown de layout + cambio rápido de modo (⌃⌘1/2/3, ⌘L) | Medio | — |
| 4 | TOC con anclas: reimplementar en `cmark_gfm_rendering.m` (arregla el TOC roto de la experimental) | Alto | — |
| 5 | Validación: tests + build + abrir y **usar de verdad** → decidir WKWebView según fricción | — | — |

## Hallazgos clave (de la investigación)
- **Mermaid v11** es post-render (independiente del motor) → portable limpio. Ojo:
  la experimental tiene mermaid **v1.2.0 viejo**; hay que llevar el v11 de la estable.
- **6 de 7 features** son ortogonales al motor (CSS/JS/UI/file-watching). El único
  punto duro es el **TOC** (cmark-gfm no emite `id` en headings; su TOC está roto).
- **WebView legacy** (no WKWebView) + APIs privadas: sirve para esta fase; la
  migración a WKWebView es un hito aparte que se decide con datos (paso 5).
- Para la visión futura: `CMARK_OPT_SOURCEPOS` (1 línea) da `data-sourcepos` por
  bloque = base del mapping inline; el puente JS↔ObjC ya existe (`MPMathJaxListener`).

## Resultado esperado
Rama experimental con cmark-gfm + mermaid v11 + todas las features = base funcional
sana, que pasaría a ser la línea principal. Ver [[vision-editor-moderno]] para la fase siguiente.
