#!/usr/bin/env bash
#
# install-latest-beta.sh — Instala a mano la última pre-release del canal beta
# (cmark-gfm) saltándose el auto-update de Sparkle.
#
# Por qué existe: los binarios van firmados *adhoc* (sin Developer ID, porque
# notarizar es de pago). Sparkle 2 verifica la firma EdDSA (válida) pero además
# exige continuidad de firma de código entre la versión instalada y la nueva;
# como adhoc no tiene identidad estable, rechaza la instalación con
# "The update is improperly signed". Resultado: el auto-update encuentra y
# descarga la versión, pero no la instala. Hasta tener Developer ID, se instala
# a mano con este script (cerrar → descargar → reemplazar → quitar cuarentena).
#
# Uso:  ./claude_tools/install-latest-beta.sh
#
set -euo pipefail

APPCAST="https://raw.githubusercontent.com/jorgeuriarte/macdown/master/appcast-beta.xml"
DEST="/Applications/MacDown cmark-gfm.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "→ Leyendo appcast: $APPCAST"
XML="$(curl -fsSL "$APPCAST")"
URL="$(printf '%s' "$XML" | grep -oE 'url="[^"]+\.zip"' | head -1 | sed -E 's/url="(.*)"/\1/')"
VER="$(printf '%s' "$XML" | grep -oE '<sparkle:shortVersionString>[^<]+' | head -1 | sed -E 's/.*>//')"
[ -n "$URL" ] || { echo "✗ No encontré la URL del .zip en el appcast"; exit 1; }
echo "→ Última beta: ${VER:-?}"
echo "  $URL"

echo "→ Descargando…"
curl -fSL "$URL" -o "$TMP/MacDown.zip"
( cd "$TMP" && unzip -q MacDown.zip )
APP="$(find "$TMP" -maxdepth 1 -name '*.app' | head -1)"
[ -n "$APP" ] || { echo "✗ El zip no contenía ninguna .app"; exit 1; }

echo "→ Cerrando la app instalada si está abierta…"
osascript -e "tell application \"$DEST\" to quit" 2>/dev/null || true
sleep 2
pkill -f "/Applications/MacDown cmark-gfm.app/Contents/MacOS/MacDown" 2>/dev/null || true
sleep 1

echo "→ Instalando en: $DEST"
rm -rf "$DEST"
ditto "$APP" "$DEST"

echo "→ Quitando cuarentena (evita el 'está dañado' de Gatekeeper)…"
xattr -cr "$DEST" 2>/dev/null || true

BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DEST/Contents/Info.plist" 2>/dev/null || echo '?')"
echo "→ Abriendo…"
open "$DEST"
echo "✓ Instalada ${VER:-?} (build ${BUILD})"
