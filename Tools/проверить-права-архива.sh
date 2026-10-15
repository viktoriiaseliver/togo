#!/bin/bash
# Того · права читаются ИЗ ПОДПИСИ архива, а не из настроек сборки.
#
# Как звать:
#   Tools/проверить-права-архива.sh build/Togo.xcarchive
#   Tools/проверить-права-архива.sh <путь>/Togo.app
#   Tools/проверить-права-архива.sh <права>.plist      ← только для приёмки
#
# Зачем, и это не теория. Проверок прав архива перед выгрузкой не было
# НИ ОДНОЙ (замер 15.10.2026: `grep iCloud` по `проверить-архив.sh`,
# `archive_fingerprint.sh`, `замер_паритета_архива.py`,
# `upload_testflight.sh`, `check_bundle_languages.sh` → три вхождения,
# и все три — комментарий у самого обходного пути).
#
# Обходной путь живой: `upload_testflight.sh` под `WITHOUT_ICLOUD=1`
# ставит вариант прав `-Personal`. Уехавший этим путём архив ломается
# не на подписи и не на запуске, а ПОЗЖЕ и ЧУЖИМИ СЛОВАМИ:
#
#     Persistence.swift:120   guard profileExists else { return true }
#                             ← профиля нет (App Store/TestFlight)
#                               → «право ЕСТЬ»
#
# Это прокси: предмет — «несёт ли подпись entitlement», а спрашивается
# «лежит ли рядом профиль». В TestFlight профиля не лежит никогда,
# значит ответ «право есть» приходит ВСЕГДА — и приложение идёт
# в CloudKit, падает и называет человеку другую причину: «войди
# в iCloud» или код ошибки сохранения.
#
# > Отказ будет нашим, а человек прочтёт его как свой.
#
# Поэтому ось здесь — не настройка, не профиль и не App ID в портале,
# а то, что ВШИТО В ПОДПИСЬ того файла, который уедет.
#
#   0  право на месте
#   1  ПРАВА НЕ ТЕ — предмет сторожа, выгрузку останавливать
#   2  звать не умеют: путь не тот, аргумента нет
#   3  ЗАМЕР НЕ СОСТОЯЛСЯ: подпись не прочиталась, бандл негоден.
#      Разбирать инструмент, а не продукт
set -euo pipefail

CONTAINER="iCloud.app.togo.diary"
GROUP="group.app.togo.diary"

if [ $# -lt 1 ]; then
    echo "Как звать: Tools/проверить-права-архива.sh <.xcarchive | .app | .plist>" >&2
    exit 2
fi

TARGET="$1"
PLIST=""
SOURCE=""
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

if [ "${TARGET##*.}" = "plist" ] && [ -f "$TARGET" ]; then
    # Вход для приёмки. Подделка подаётся НАСТОЯЩИМ входом судящей
    # половины, а не обходом её: иначе приёмка доказывала бы работу
    # того, чего в воротах нет.
    PLIST="$TARGET"
    SOURCE="файл прав (режим приёмки, подписи не читаю)"
else
    if [ -d "$TARGET/Products/Applications" ]; then
        APP="$(find "$TARGET/Products/Applications" -maxdepth 1 -name '*.app' | head -1)"
    elif [ -d "$TARGET" ] && [ "${TARGET##*.}" = "app" ]; then
        APP="$TARGET"
    else
        echo "✗ не нашёл .app по пути $TARGET" >&2
        exit 2
    fi
    [ -n "${APP:-}" ] && [ -d "$APP" ] || { echo "✗ не нашёл .app внутри $TARGET" >&2; exit 2; }

    # `codesign` печатает права в stdout, а свои жалобы в stderr,
    # и при отсутствии подписи возвращает НЕ НОЛЬ. Код берём у него
    # самого, а не у конвейера: иначе отказ подписи приедет нулём.
    CODE=0
    codesign -d --entitlements :- --xml "$APP" > "$W/raw" 2> "$W/err" || CODE=$?
    if [ "$CODE" -ne 0 ] || [ ! -s "$W/raw" ]; then
        echo "✗ ЗАМЕР НЕ СОСТОЯЛСЯ: подпись $(basename "$APP") не прочиталась (codesign вернул $CODE)." >&2
        sed 's/^/    /' "$W/err" >&2 || true
        echo "  Неподписанный или недособранный бандл о правах не отвечает вовсе." >&2
        echo "  Это не «прав нет» — это «спросить было не у кого»." >&2
        exit 3
    fi
    # До xml-плиста может идти мусор из DER-половины подписи.
    # Имя переменной в awk — только латиницей: кириллическое не имя,
    # и awk падает синтаксисом внутри ветки, ради которой написан.
    awk '/<\?xml/{p=1} p' "$W/raw" > "$W/ent.plist"
    [ -s "$W/ent.plist" ] || { echo "✗ ЗАМЕР НЕ СОСТОЯЛСЯ: в выводе codesign нет xml." >&2; exit 3; }
    PLIST="$W/ent.plist"
    SOURCE="подпись $(basename "$APP")"
fi

echo "── права читаю из: ${SOURCE}"

# Читаем плист питоном, а НЕ `plutil -extract`, и это не вкусовщина —
# замер 15.10.2026 подделкой на здоровых правах:
#
#     plutil -extract com.apple.developer.icloud-services raw -o - …
#        → «НЕТ КЛЮЧА» при ключе, который в файле ЕСТЬ
#     plutil -extract com.apple.security.application-groups raw -o - …
#        → «20» вместо списка групп
#
# Причина: у `plutil -extract` точка — РАЗДЕЛИТЕЛЬ пути, а у ключей
# entitlements точка в имени. Запрос читался как «com → apple →
# developer → …», и ни одного такого вложения в плисте нет.
#
# > Ворота на этом родились бы КРАСНЫМИ всегда, и читалось бы это
# > как дефект продукта: «права не те» на правах, которые те.
#
# Поймала подделка, не чтение: здоровый вход дал отказ, и расхождение
# с объявленным до прогона исходом было единственным признаком.
ent_value() {
    PLIST="$PLIST" python3 -c '
import os, plistlib, sys
with open(os.environ["PLIST"], "rb") as f:
    права = plistlib.load(f)
значение = права.get(sys.argv[1])
if значение is None:
    sys.exit(0)
if isinstance(значение, (list, tuple)):
    print(" ".join(str(э) for э in значение))
else:
    print(значение)
' "$1" 2>/dev/null || true
}

# APP_GROUPS, а не GROUPS: `GROUPS` — ВСТРОЕННАЯ переменная bash
# (список gid текущего пользователя). Присваивание в неё молча
# не состоялось, а чтение дало «20» — правдоподобное число вместо
# списка групп, и сторож краснел на здоровых правах. Вторая подделка
# того же захода: имя, совпавшее со встроенным, отвечает про себя.
CONTAINERS="$(ent_value com.apple.developer.icloud-container-identifiers)"
SERVICES="$(ent_value com.apple.developer.icloud-services)"
APP_GROUPS="$(ent_value com.apple.security.application-groups)"

printf "   icloud-container-identifiers: %s\n" "${CONTAINERS:-НЕТ КЛЮЧА}"
printf "   icloud-services:              %s\n" "${SERVICES:-НЕТ КЛЮЧА}"
printf "   application-groups:           %s\n" "${APP_GROUPS:-НЕТ КЛЮЧА}"

FAIL=0

case "$CONTAINERS" in
    *"$CONTAINER"*) ;;
    *)  echo "✗ в подписи НЕТ контейнера «${CONTAINER}»." >&2
        FAIL=1 ;;
esac

case "$SERVICES" in
    *CloudKit*) ;;
    *)  echo "✗ в подписи НЕТ сервиса CloudKit." >&2
        FAIL=1 ;;
esac

case "$APP_GROUPS" in
    *"$GROUP"*) ;;
    *)  echo "✗ в подписи НЕТ общей группы «${GROUP}»." >&2
        echo "  Без неё виджет и «остров» читают СВОЁ пустое хранилище:" >&2
        echo "  на экране блокировки человек увидит приложение без данных." >&2
        FAIL=1 ;;
esac

if [ "$FAIL" -ne 0 ]; then
    echo "" >&2
    # Обратные кавычки здесь исполнил бы шелл — ровно то, на чём
    # 14.10 потеряли коммит. Внутри двойных кавычек только «ёлочки».
    echo "  Это вариант прав БЕЗ iCloud — «WITHOUT_ICLOUD=1», «-Personal»." >&2
    echo "  Такой архив выгружать нельзя: приложение объявит право своим" >&2
    echo "  (Persistence.swift:120 спрашивает профиль, а не подпись)," >&2
    echo "  пойдёт в CloudKit и упадёт, назвав человеку чужую причину." >&2
    echo "  Общий дневник у мамы при этом не заработает вовсе." >&2
    exit 1
fi

echo "✓ право на iCloud вшито в подпись: контейнер, CloudKit и общая группа."
echo "  Чего это НЕ значит: что обмен работает. Подпись говорит только,"
echo "  что приложению РАЗРЕШЕНО спрашивать CloudKit. Доехала ли запись"
echo "  до второго телефона — неизмеримо без живого iCloud Виктории."
