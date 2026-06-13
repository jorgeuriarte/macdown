# Rama experimental: motor de render cmark-gfm

Esta rama (`experiment/cmark-gfm`) sustituye el motor de render **hoedown** por
**cmark-gfm** (el parser CommonMark + GFM de GitHub), basándose en el trabajo de
**Carl / SiggeMcKvack** ([SiggeMcKvack/macdown](https://github.com/SiggeMcKvack/macdown)).

## Qué cambia

- Render con cmark-gfm (CommonMark estricto + extensiones GFM), más fiel a GitHub.
- Build arm64, deployment macOS 11.0, Sparkle 2 (firma DSA compatible con el canal beta).

## ⚠️ Qué se pierde respecto a la versión estable

Al cambiar de motor se eliminan extensiones que dependían de hoedown:
**highlight (==texto==), superscript (^), underline y quote**.

## Distribución

Las builds de esta rama se publican como **pre-releases** en el **canal
experimental**. En la app: Preferencias → marcar *"Include experimental (beta)
updates"*. Tags con guion (p.ej. `v0.9-cmark.1`) → canal experimental.

> No mergear a `master`: es una línea de evaluación del motor, no la estable.
