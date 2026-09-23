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

# Имя переменной у нас и у соседних проектов разошлось: здесь ждали
# `ASC_ISSUER`, а `Gamut/.env.asc` кладёт `ASC_ISSUER_ID`. 23.09.2026
# выгрузка Виктории упала на этом и была обойдена руками — то есть
# завтра наступили бы снова. Принимаем оба и говорим, какое нашлось:
# «ключа нет» и «ключ назван иначе» — разные беды с разным лечением.
if [ -z "${ASC_ISSUER:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ]; then
    ASC_ISSUER="$ASC_ISSUER_ID"
    echo "── issuer взят из ASC_ISSUER_ID"
fi

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

# Что нас попросили сделать — решаем до проверок: у выгрузки готового
# архива и у полного цикла разные требования к дереву.
UPLOAD_ONLY=""
DIRTY_ALLOWED="${DIRTY_OK:-}"
for arg in "$@"; do
    case "$arg" in
        --только-выгрузка) UPLOAD_ONLY=1 ;;
        --грязно) DIRTY_ALLOWED=1 ;;
    esac
done

# Дерево обязано быть чистым, и это отказ, а не предупреждение.
#
# **`xcodebuild` архивирует диск, а не коммит.** 23.09.2026 это едва
# не стоило поставки дважды за час: в дереве лежала незаконченная
# правка, а в другой раз — намеренно испорченная строка, оставленная
# после проверки сторожа подделкой. Оба раза спас чужой таймаут,
# а не проверка.
#
# Сборка, собранная с грязного дерева, неотличима снаружи от честной:
# номер тот же, подпись та же, «что тестировать» от коммита, которого
# в бинарнике уже нет.
#
# `--грязно` оставлено намеренно: бывает нужно собрать с правкой
# в руках. Но это должно быть сказано вслух, а не случиться само.
#
# Имена переменных здесь латиницей, как и всюду в файле: `bash`
# кириллическое имя за имя не считает, присваивание молча падает
# («command not found»), а следующая строка выполняется как ни в чём
# не бывало. Один рабочий файл этим уже был испорчен — правило
# записано в своде, и я нарушил его в этой же правке, прежде чем
# заметить.
#
# При `--только-выгрузка` не проверяется вовсе, и это не послабление:
# архив уже собран, дерево на него не влияет никак. Наоборот —
# типичный случай в том, что после сборки легли коммиты журнала
# и статуса, и требовать чистоты значило бы заставить пересобирать
# ради ничего.
if [ -z "$UPLOAD_ONLY" ] && [ -z "$DIRTY_ALLOWED" ]; then
    DIRTY="$(git --no-optional-locks status --porcelain)"
    if [ -n "$DIRTY" ]; then
        fail "дерево не чистое — архив возьмёт диск, а не коммит:

$DIRTY

Закоммить своё или запусти с --грязно, если это намеренно."
    fi
fi

ARCHIVE="build/Togo.xcarchive"

# 3. Готовый архив не стираем молча.
#
# Скрипт делает свой полный цикл — тесты, архив, выгрузка — и раньше
# начинался с `rm -rf` чужого архива. 23.09 так пропала собранная
# и проверенная сборка 189: её паспорт (номер, путь, `sha256`) уже был
# отправлен, а проверять стало нечего.
#
# Экспорт готового архива — минуты, полный цикл — полчаса. Поэтому
# `--только-выгрузка` полезнее вопроса.
if [ "${1:-}" = "--только-выгрузка" ] || [ "${2:-}" = "--только-выгрузка" ]; then
    [ -d "$ARCHIVE" ] || fail "архива нет: $ARCHIVE. Собери его — make archive."
    UPLOAD_ONLY=1
    echo "── беру готовый архив $(plutil -extract ApplicationProperties.CFBundleVersion raw "$ARCHIVE/Info.plist")"
else
    UPLOAD_ONLY=""
    if [ -d "$ARCHIVE" ]; then
        echo "── стираю прежний архив $(plutil -extract ApplicationProperties.CFBundleVersion raw "$ARCHIVE/Info.plist" 2>/dev/null || echo '?') — он пересобирается"
    fi
    rm -rf "$ARCHIVE" build/export
fi

if [ -z "$UPLOAD_ONLY" ]; then
echo "── тесты"
# Симулятор берётся по UDID тем же подборщиком, что у `make unit`, а не
# по имени. `name=iPhone 17 Pro` без версии разрешается в `OS:latest`:
# стоит рядом появиться рантайму новее того, на котором заведён этот
# симулятор (27.0 при устройстве на 26.5), и xcodebuild отвечает
# «устройство не найдено» — при том, что оно есть и видно в `simctl list`.
# Выгрузка падала на шаге тестов, не дойдя до архива.
#
# Имя переменной латиницей, в отличие от остального: имена переменных
# в shell обязаны быть из ASCII, и `СИМУЛЯТОР=...` bash принимает
# за команду — «command not found».
#
# `tail -1` обязателен: подборщик печатает в stdout сначала строку
# «Беру готовый: …», и только последняя строка — UDID.
SIM="$(python3 Tools/ci_simulator.py | tail -1)"
xcodebuild test \
    -project Togo.xcodeproj -scheme Togo \
    -destination "platform=iOS Simulator,id=${SIM}" \
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
else
    # Номер берём из готового архива, а не из `git rev-list`: после
    # сборки могли лечь коммиты — журнал, статус, — и тогда «номер»
    # и «то, что в бинарнике» разошлись бы молча. Info.plist архива
    # знает правду; git знает только текущее дерево.
    BUILD="$(plutil -extract ApplicationProperties.CFBundleVersion raw "$ARCHIVE/Info.plist")"
    VERSION="$(plutil -extract ApplicationProperties.CFBundleShortVersionString raw "$ARCHIVE/Info.plist")"
    AUTH=(-authenticationKeyPath "$(cd "$(dirname "$ASC_KEY")" && pwd)/$(basename "$ASC_KEY")"
          -authenticationKeyID "$ASC_KEY_ID"
          -authenticationKeyIssuerID "$ASC_ISSUER")
    echo "── выгружаю готовый архив $VERSION ($BUILD), не пересобирая"
fi

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

Скрипт publish_beta.sh пишет заметки к сборке, «что тестировать» и выдаёт
её внутренней группе. Внешней сборку добавляет Apple после бета-ревью —
Tools/submit_beta_review.sh.
DONE
