#!/bin/bash
# Собирает и ставит Того на подключённый iPhone.
#
#   make device TEAM=L7CPH7W5QW            # полные права: App Groups и iCloud
#   make device TEAM=XXXXXXXXXX PERSONAL=1 # бесплатная команда разработчика
#
# По умолчанию подписывает тем же набором прав, что уходит в App Store:
# App Groups и iCloud. Иначе телефон получает не то приложение, которое
# проверяют тестировщики, — без общего дневника и с виджетом, который
# не видит общего хранилища.
#
# `PERSONAL=1` — для бесплатной команды разработчика: она App Groups
# и iCloud не выдаёт, и без этого варианта подпись падает ещё до сборки.
# Приложение при этом работает целиком, только дневник хранится локально;
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

VARIANT=""
if [ -n "${PERSONAL:-}" ]; then
    VARIANT="-Personal"
fi

echo "Устройство: $DEVICE_NAME"
echo "Команда:    $TEAM"
echo "Права:      ${VARIANT:-полные (App Groups и iCloud)}"
echo

xcodebuild \
    -project Togo.xcodeproj \
    -scheme Togo \
    -configuration Debug \
    -destination "platform=iOS,id=$DEVICE_UDID" \
    -derivedDataPath build/device \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" \
    ENTITLEMENTS_VARIANT="$VARIANT" \
    build | tail -3

APP="$(find build/device/Build/Products/Debug-iphoneos -maxdepth 1 -name 'Togo.app' | head -1)"
if [ -z "$APP" ]; then
    echo "Сборка не дала Togo.app — смотри ошибки выше."
    exit 1
fi

echo "Ставлю $APP"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

cat <<NOTE

Готово. Приложение на телефоне.

Первый запуск: Настройки → Основные → VPN и управление устройством →
доверять разработчику.
$([ -n "${PERSONAL:-}" ] \
  && echo "Подпись бесплатной команды живёт 7 дней — потом поставить заново той же командой." \
  || echo "Подпись платной команды живёт год.")
NOTE
