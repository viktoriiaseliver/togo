#!/bin/bash
# Собирает Того и отправляет сборку в TestFlight.
#
#   Tools/upload_testflight.sh
#
# Что нужно один раз положить в окружение (см. docs/APP-STORE.md):
#
#   TEAM        Team ID из App Store Connect → Membership
#   ASC_KEY_ID  идентификатор ключа App Store Connect API
#   ASC_ISSUER  Issuer ID оттуда же
#   ASC_KEY     путь к файлу AuthKey_XXXXXXXX.p8
#
# Ключ API, а не пароль приложения: пароль требует ввода руками
# и живёт до первой смены пароля Apple ID, а ключ работает молча
# и отзывается одной кнопкой.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() { echo "✗ $1" >&2; exit 1; }

[ -n "${TEAM:-}" ]       || fail "не задан TEAM — Team ID из App Store Connect"
[ -n "${ASC_KEY_ID:-}" ] || fail "не задан ASC_KEY_ID"
[ -n "${ASC_ISSUER:-}" ] || fail "не задан ASC_ISSUER"
[ -n "${ASC_KEY:-}" ]    || fail "не задан ASC_KEY — путь к AuthKey_*.p8"
[ -f "$ASC_KEY" ]        || fail "файл ключа не найден: $ASC_KEY"

# Номер сборки — количество коммитов. Он обязан расти от загрузки
# к загрузке, и git считает это надёжнее человека.
BUILD="$(git rev-list --count HEAD)"
VERSION="$(grep '^MARKETING_VERSION' Configuration/Shared.xcconfig | sed 's/.*= *//')"

echo "── Того $VERSION ($BUILD) → TestFlight"

ARCHIVE="build/Togo.xcarchive"
rm -rf "$ARCHIVE" build/export

echo "── тесты"
xcodebuild test \
    -project Togo.xcodeproj -scheme Togo \
    -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:TogoTests \
    -quiet

echo "── архив"
xcodebuild archive \
    -project Togo.xcodeproj -scheme Togo \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -configuration Release \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" \
    BUILD_NUMBER="$BUILD" \
    -quiet

# Team ID подставляем в копию: сам файл в репозитории остаётся без него.
OPTIONS="build/ExportOptions.plist"
sed "s/TEAM_ID_PLACEHOLDER/$TEAM/" Configuration/ExportOptions.plist > "$OPTIONS"

echo "── загрузка"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$OPTIONS" \
    -exportPath build/export \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$(cd "$(dirname "$ASC_KEY")" && pwd)/$(basename "$ASC_KEY")" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER"

cat <<DONE

Готово. Сборка $VERSION ($BUILD) уехала в App Store Connect.

Дальше — там:
  1. Обработка занимает 5–30 минут, потом сборка появится в TestFlight.
  2. Экспортное соответствие уже отвечено в Info.plist
     (ITSAppUsesNonExemptEncryption = false) — вопроса не будет.
  3. Добавить сборку в группу тестировщиков.

Внутренним тестировщикам (до 100 человек из вашей команды) сборка
доступна сразу. Внешним — после проверки, обычно за сутки.
DONE
