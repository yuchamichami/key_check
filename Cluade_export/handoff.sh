#!/usr/bin/env bash
# KeyCheck handoff — turn the iconset PNGs into .icns and update Info.plist.
# Run from project root after copying export/ into the key_check repo root.
set -euo pipefail

ICONSET_SRC="export/iconset"
ICONSET_DIR="KeyCheck.iconset"

# 1) Rename _2x → @2x (filesystem-safe → Apple's required name)
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
for f in "$ICONSET_SRC"/*.png; do
  base=$(basename "$f")
  fixed=${base/_2x/@2x}
  cp "$f" "$ICONSET_DIR/$fixed"
done

# 2) Build .icns
iconutil -c icns "$ICONSET_DIR" -o KeyCheck.icns
echo "✓ KeyCheck.icns generated"

# 3) Patch Info.plist
if [ -f Info.plist ]; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string KeyCheck" Info.plist 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile KeyCheck" Info.plist
  echo "✓ Info.plist CFBundleIconFile = KeyCheck"
fi

echo "Now run ./build.sh to build KeyCheck.app with the new icon."
