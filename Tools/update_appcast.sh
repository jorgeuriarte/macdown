#!/usr/bin/env bash
# Genera un appcast de Sparkle 2 (firma EdDSA) con la release indicada como único
# item (Sparkle solo necesita conocer la última versión para ofrecer la update).
#
# Uso:
#   Tools/update_appcast.sh <zip> <version> <shortVersion> <enclosureURL> \
#                           <edKeyFile> <appcastOut> [minSystemVersion] [pubDate]
#
#   <zip>            ruta al .zip de la app (se firma y se mide su tamaño)
#   <version>       CFBundleVersion (entero creciente; sparkle:version)
#   <shortVersion>  CFBundleShortVersionString (p.ej. 0.8.7-ju)
#   <enclosureURL>  URL pública del .zip (asset de la GitHub Release)
#   <edKeyFile>     clave privada EdDSA (NUNCA se versiona; viene de un secreto)
#   <appcastOut>    ruta de salida del appcast.xml
#   [minSystem]     versión mínima de macOS (por defecto 10.13)
#   [pubDate]       fecha RFC-822 (por defecto: ahora en UTC)
#
# Requiere la herramienta sign_update de Sparkle 2 (Pods/Sparkle/bin/sign_update
# tras `pod install`, o la ruta indicada en la variable de entorno SIGN_UPDATE).
set -euo pipefail

ZIP="$1"; VERSION="$2"; SHORTVER="$3"; URL="$4"; EDKEY="$5"; OUT="$6"
MINSYS="${7:-10.13}"
PUBDATE="${8:-$(date -u "+%a, %d %b %Y %H:%M:%S +0000")}"

SIGNTOOL="${SIGN_UPDATE:-Pods/Sparkle/bin/sign_update}"

[ -f "$ZIP" ]    || { echo "ERROR: no existe el zip $ZIP" >&2; exit 1; }
[ -f "$EDKEY" ]  || { echo "ERROR: no existe la clave EdDSA $EDKEY" >&2; exit 1; }
[ -x "$SIGNTOOL" ] || { echo "ERROR: sign_update no encontrado en $SIGNTOOL" >&2; exit 1; }

# sign_update emite directamente:  sparkle:edSignature="..." length="..."
SIG_AND_LENGTH=$("$SIGNTOOL" --ed-key-file "$EDKEY" "$ZIP")

TITLE="MacDown ($(basename "$OUT" .xml))"

cat > "$OUT" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>${TITLE}</title>
    <link>https://raw.githubusercontent.com/jorgeuriarte/macdown/master/$(basename "$OUT")</link>
    <description>Actualizaciones del fork de mantenimiento de MacDown.</description>
    <language>es</language>
    <item>
      <title>Versión ${SHORTVER}</title>
      <pubDate>${PUBDATE}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${SHORTVER}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MINSYS}</sparkle:minimumSystemVersion>
      <enclosure
        url="${URL}"
        ${SIG_AND_LENGTH}
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

echo "appcast generado: $OUT (v${SHORTVER}, build ${VERSION})"
