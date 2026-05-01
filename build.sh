#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="KeyCheck"
APP_DIR="${APP_NAME}.app"

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

xcrun swiftc \
    -O \
    -parse-as-library \
    -target arm64-apple-macos13 \
    -framework SwiftUI \
    -framework AppKit \
    -framework AVFoundation \
    -o "${APP_DIR}/Contents/MacOS/${APP_NAME}" \
    main.swift

cp Info.plist "${APP_DIR}/Contents/Info.plist"

# Pick a stable code-signing identity so TCC (Input Monitoring) survives rebuilds.
# Priority:
#   1. Apple Development / Developer ID (best — real Apple-issued cert)
#   2. KeyCheck Local Signer (self-signed, from setup_signing.sh)
#   3. Ad-hoc (permission resets every rebuild)
IDENTITY=""
for prefix in "Apple Development" "Developer ID Application" "Apple Distribution" "KeyCheck Local Signer"; do
    found=$(security find-identity -v -p codesigning 2>/dev/null \
            | awk -F'"' -v p="$prefix" '$2 ~ p {print $2; exit}')
    if [ -n "$found" ]; then
        IDENTITY="$found"
        break
    fi
done

if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" "${APP_DIR}" >/dev/null
    echo "Signed with: $IDENTITY"
    echo "  ↳ TCC permission will persist across rebuilds."
else
    codesign --force --sign - "${APP_DIR}" >/dev/null 2>&1 || true
    echo "Signed ad-hoc (no stable code-signing cert found)."
    echo "  ↳ Input Monitoring permission may reset on rebuild."
fi

echo "Built ${APP_DIR}"
echo "Run: open ${APP_DIR}"
