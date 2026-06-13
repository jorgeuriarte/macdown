#!/usr/bin/env bash
# Genera un appcast de Sparkle 1 (firma DSA) con la release indicada como único
# item (Sparkle solo necesita conocer la última versión para ofrecer la update).
#
# Uso:
#   Tools/update_appcast.sh <zip> <version> <shortVersion> <enclosureURL> \
#                           <privKeyFile> <appcastOut> [minSystemVersion] [pubDate]
#
#   <zip>            ruta al .zip de la app (se firma y se mide su tamaño)
#   <version>       CFBundleVersion (entero creciente; sparkle:version)
#   <shortVersion>  CFBundleShortVersionString (p.ej. 0.8.3)
#   <enclosureURL>  URL pública del .zip (asset de la GitHub Release)
#   <privKeyFile>   clave privada DSA (NUNCA se versiona; viene de un secreto)
#   <appcastOut>    ruta de salida del appcast.xml
#   [minSystem]     versión mínima de macOS (por defecto 10.13)
#   [pubDate]       fecha RFC-822 (por defecto: ahora en UTC)
set -euo pipefail

ZIP="$1"; VERSION="$2"; SHORTVER="$3"; URL="$4"; PRIVKEY="$5"; OUT="$6"
MINSYS="${7:-10.13}"
PUBDATE="${8:-$(date -u "+%a, %d %b %Y %H:%M:%S +0000")}"

[ -f "$ZIP" ] || { echo "ERROR: no existe el zip $ZIP" >&2; exit 1; }
[ -f "$PRIVKEY" ] || { echo "ERROR: no existe la clave privada $PRIVKEY" >&2; exit 1; }

# Tamaño del archivo (macOS y Linux)
LENGTH=$(stat -f%z "$ZIP" 2>/dev/null || stat -c%s "$ZIP")

# Firma DSA-SHA1 en base64 (idéntico a lo que verifica Sparkle 1 con dsa_pub.pem)
SIG=$(openssl dgst -sha1 -binary < "$ZIP" | openssl dgst -sha1 -sign "$PRIVKEY" | openssl enc -base64 | tr -d '\n')

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
        sparkle:dsaSignature="${SIG}"
        length="${LENGTH}"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

echo "appcast generado: $OUT (v${SHORTVER}, build ${VERSION}, ${LENGTH} bytes)"
