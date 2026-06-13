# Actualizaciones automáticas (Sparkle)

MacDown usa **Sparkle 1** para actualizarse. Este fork lo apunta a **nuestras
propias releases** en lugar del feed (muerto) del proyecto original.

## Cómo funciona

1. La app trae un `SUUpdater` configurado con dos feeds en `MacDown-Info.plist`:
   - `SUFeedURL` → `https://raw.githubusercontent.com/jorgeuriarte/macdown/master/appcast.xml` (estable)
   - `SUBetaFeedURL` → `…/appcast-beta.xml` (beta / experimental)
2. "Check for Updates…" descarga el appcast, compara `sparkle:version`
   (= `CFBundleVersion`, creciente) con la instalada y, si hay una más nueva,
   descarga el `.zip`, **verifica la firma DSA** con `dsa_pub.pem` y lo instala.
3. El feed que se consulta lo decide `feedURLStringForUpdater:` según la
   preferencia `updateIncludesPreReleases` (estable vs beta).

## Cómo se publican las actualizaciones

El workflow `.github/workflows/build.yml`, al construir un tag `vX.Y.Z`:
1. Compila y publica la GitHub Release con `MacDown.zip` + `MacDown.dmg`.
2. Firma el `.zip` con la clave privada DSA (secreto `SPARKLE_DSA_PRIVATE_KEY`)
   y genera el appcast con `Tools/update_appcast.sh`.
3. Commitea el appcast a `master` (`[skip ci]`), de donde lo sirve raw.

**Canales por convención de tag:** `vX.Y.Z` → estable; `vX.Y.Z-loquesea`
(con guion, p.ej. `v0.9-cmark`) → beta/experimental.

## Claves

- Pública: `MacDown/Resources/dsa_pub.pem` (en el repo).
- Privada: **solo** en el secreto de Actions `SPARKLE_DSA_PRIVATE_KEY`. Nunca se versiona.

## Lo que falta para "uso completo" sin fricción

- **Firma Developer ID + notarización** (Apple Developer Program, de pago). Sin
  ella, la actualización se instala pero Gatekeeper la marca como de
  "desarrollador no identificado". El workflow está listo para enchufar la firma.
- **Primer salto manual**: una versión instalada con la config antigua (feed/clave
  del proyecto original) no puede validar nuestro appcast. Hay que instalar **a
  mano una vez** la primera release con la config nueva (v0.8.3); a partir de ahí,
  el auto-update funciona solo.

## Idea: canal de actualización seleccionable

Se puede exponer un popup en Preferencias → Actualizaciones para elegir canal
(**Estable / Experimental**), ambos firmados con nuestra clave. Apuntar a la
versión *oficial* del proyecto original no es viable con Sparkle 1: la app valida
con una única clave pública (la nuestra) y el feed oficial va firmado con otra
clave distinta (además de estar abandonado).
