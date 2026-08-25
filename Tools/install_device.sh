#!/bin/bash
# Собирает и ставит Того на подключённый iPhone.
#
#   make device TEAM=L7CPH7W5QW
#
# Подписывает вариантом прав без App Groups и iCloud: бесплатная команда
# разработчика их не выдаёт. Приложение от этого работает целиком, только
# дневник хранится локально, а виджет не видит общего хранилища —
# на экране «Перенос» это написано прямо.
set -euo pipefail

TEAM="${1:?укажи Team ID}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEVICE_LINE="$(python3 Tools/pick_device.py || true)"
if [ -z "$DEVICE_LINE" ]; then
    echo "Телефон не найден. Подключи кабелем, разблокируй и подтверди «Доверять»."
    exit 1
fi

DEVICE_ID="$(echo "$DEVICE_LINE" | cut -d' ' -f1)"
DEVICE_UDID="$(echo "$DEVICE_LINE" | cut -d' ' -f2)"
DEVICE_NAME="$(echo "$DEVICE_LINE" | cut -d' ' -f3-)"

echo "Устройство: $DEVICE_NAME"
echo "Команда:    $TEAM"
echo

xcodebuild \
    -project Togo.xcodeproj \
    -scheme Togo \
    -configuration Debug \
    -destination "platform=iOS,id=$DEVICE_UDID" \
    -derivedDataPath build/device \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" \
    ENTITLEMENTS_VARIANT=-Personal \
    build | tail -3

APP="$(find build/device/Build/Products/Debug-iphoneos -maxdepth 1 -name 'Togo.app' | head -1)"
if [ -z "$APP" ]; then
    echo "Сборка не дала Togo.app — смотри ошибки выше."
    exit 1
fi

echo "Ставлю $APP"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

cat <<'NOTE'

Готово. Приложение на телефоне.

Первый запуск: Настройки → Основные → VPN и управление устройством →
доверять разработчику. Бесплатная подпись живёт 7 дней — потом поставить
заново той же командой.
NOTE
