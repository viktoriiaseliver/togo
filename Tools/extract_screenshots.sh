#!/bin/bash
# Достаёт вложения-скриншоты из .xcresult в обычную папку с PNG.
#
#   Tools/extract_screenshots.sh build/Screens.xcresult fastlane/screenshots
set -euo pipefail

BUNDLE="${1:?путь к .xcresult}"
OUT="${2:-fastlane/screenshots}"

mkdir -p "$OUT"
xcrun xcresulttool export attachments \
    --path "$BUNDLE" \
    --output-path "$OUT" \
    --test-id-includes-scheme false 2>/dev/null || \
xcrun xcresulttool export attachments --path "$BUNDLE" --output-path "$OUT"

echo "Скриншоты: $OUT"
ls -1 "$OUT" | head -20
