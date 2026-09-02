#!/bin/bash
# Забирает с телефона журнал действий — что человек нажимал и чем это
# кончилось. Нужен после пары недель живого пользования: по нему видно,
# где приложение мешало, а не где оно упало.
#
#   Tools/pull_usage_log.sh
#
# В журнале только имена действий: ни граммов, ни заметок, ни клички.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEVICE_LINE="$(python3 Tools/pick_device.py || true)"
if [ -z "$DEVICE_LINE" ]; then
    echo "Телефон не найден."
    exit 1
fi
DEVICE_ID="$(echo "$DEVICE_LINE" | cut -d' ' -f1)"

OUT="build/usage.jsonl"
mkdir -p build
xcrun devicectl device copy from \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier app.togo.diary \
    --source Documents/usage.jsonl \
    --destination "$OUT" >/dev/null

echo "--- $OUT · $(wc -l < "$OUT" | tr -d ' ') действий"
echo "Отчёт целиком читается в приложении: Настройки → Данные → Журнал действий."
