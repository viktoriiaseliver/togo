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

# Team берём из конфигурации проекта: он там и так записан, и держать
# его в двух местах — верный способ однажды загрузить не туда.
TEAM="${TEAM:-$(grep '^DEVELOPMENT_TEAM' Configuration/Shared.xcconfig | sed 's/.*= *//')}"
[ -n "$TEAM" ] || fail "не задан TEAM — Team ID из App Store Connect"

# Ключ ищем там, где его кладут по умолчанию: не заставлять же вводить
# путь каждый раз.
if [ -z "${ASC_KEY:-}" ]; then
    ASC_KEY="$(ls "$HOME/.appstoreconnect/private_keys/"AuthKey_*.p8 2>/dev/null | head -1)"
fi
[ -n "${ASC_KEY:-}" ] || fail "ключ не найден. Положи AuthKey_*.p8 в ~/.appstoreconnect/private_keys/"
[ -f "$ASC_KEY" ]     || fail "файл ключа не найден: $ASC_KEY"

# Key ID — это часть имени файла, спрашивать её отдельно незачем.
ASC_KEY_ID="${ASC_KEY_ID:-$(basename "$ASC_KEY" .p8 | sed 's/^AuthKey_//')}"

if [ -z "${ASC_ISSUER:-}" ]; then
    fail "не задан ASC_ISSUER.

Issuer ID вывести неоткуда — его показывает только App Store Connect:
  Users and Access → Integrations → App Store Connect API,
  строка «Issuer ID» над списком ключей. Это UUID.

  export ASC_ISSUER=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
fi

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

# Без iCloud и общей группы. Нужно, пока в портале не заведены
# `group.app.togo.diary` и контейнер `iCloud.app.togo.diary`: без них
# подпись падает ещё до сборки. Приложение при этом работает целиком,
# только дневник не синхронизируется между устройствами — ровно так же,
# как оно сейчас работает на телефоне.
VARIANT=""
if [ -n "${WITHOUT_ICLOUD:-}" ]; then
    VARIANT="-Personal"
    echo "── без iCloud и общей группы"
fi

AUTH=(-authenticationKeyPath "$(cd "$(dirname "$ASC_KEY")" && pwd)/$(basename "$ASC_KEY")"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER")

echo "── архив"
xcodebuild archive \
    -project Togo.xcodeproj -scheme Togo \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -configuration Release \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" \
    BUILD_NUMBER="$BUILD" \
    ENTITLEMENTS_VARIANT="$VARIANT" \
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
    "${AUTH[@]}"

cat <<DONE

Готово. Сборка $VERSION ($BUILD) уехала в App Store Connect.

Обработка занимает 5–30 минут. Экспортное соответствие уже отвечено
в Info.plist (ITSAppUsesNonExemptEncryption = false) — вопроса не будет.

Дальше обязателен второй шаг:

    make beta        # или Tools/publish_beta.sh

Загрузка сборку только приносит. Пока её не добавили в группу, её
не видит никто — включая своих. Сборки 25 и 30 так и пролежали ничьими
неделю, и выглядело это как «TestFlight не приходит».

`publish_beta.sh` пишет заметки к сборке, «что тестировать» и выдаёт
её внутренней группе. Внешней сборку добавляет Apple после бета-ревью —
Tools/submit_beta_review.sh.
DONE
