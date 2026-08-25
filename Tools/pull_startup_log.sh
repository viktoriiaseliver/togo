#!/bin/bash
# Забирает с телефона крошки запуска — то, что приложение записало о себе,
# пока поднималось. Нужно, когда оно падает на устройстве: «signal 5»
# без строки и без причины сам по себе ничего не объясняет.
#
#   Tools/pull_startup_log.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEVICE_LINE="$(python3 Tools/pick_device.py || true)"
if [ -z "$DEVICE_LINE" ]; then
    echo "Телефон не найден."
    exit 1
fi
DEVICE_ID="$(echo "$DEVICE_LINE" | cut -d' ' -f1)"

OUT="build/startup.log"
mkdir -p build
xcrun devicectl device copy from \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier app.togo.diary \
    --source Documents/startup.log \
    --destination "$OUT" >/dev/null

echo "--- $OUT"
cat "$OUT"
