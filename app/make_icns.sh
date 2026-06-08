#!/bin/bash
# Génère app/Captioneer.icns à partir du fichier source PNG/JPG 1024x1024.
# Usage : ./app/make_icns.sh [path/to/source-1024x1024.png]
# Sans argument : prend la 1re image trouvée dans Captioneer.icon/Assets/
# (n'importe quel nom de fichier .png/.jpg/.jpeg).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$HERE")"
DEFAULT_SRC="$(find "$REPO/Captioneer.icon/Assets" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) 2>/dev/null | sort | head -1)"
SRC="${1:-$DEFAULT_SRC}"
OUT_ICNS="$HERE/Captioneer.icns"

[ -n "$SRC" ] && [ -f "$SRC" ] || { echo "Source introuvable : aucune image dans Captioneer.icon/Assets/ (ni argument fourni)" >&2; exit 1; }

WORK="$(/usr/bin/mktemp -d /tmp/Captioneer-icns.XXXXXX)"
SET="$WORK/Captioneer.iconset"
mkdir -p "$SET"

PNG="$WORK/source.png"
/usr/bin/sips -s format png "$SRC" --out "$PNG" >/dev/null

emit() { /usr/bin/sips -z "$1" "$1" "$PNG" --out "$SET/$2" >/dev/null; }
emit 16   icon_16x16.png
emit 32   icon_16x16@2x.png
emit 32   icon_32x32.png
emit 64   icon_32x32@2x.png
emit 128  icon_128x128.png
emit 256  icon_128x128@2x.png
emit 256  icon_256x256.png
emit 512  icon_256x256@2x.png
emit 512  icon_512x512.png
emit 1024 icon_512x512@2x.png

/usr/bin/iconutil -c icns "$SET" -o "$OUT_ICNS"
rm -rf "$WORK"

echo "OK : $OUT_ICNS ($(/usr/bin/stat -f%z "$OUT_ICNS") octets)"
