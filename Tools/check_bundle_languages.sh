#!/bin/bash
# Того · языки считаются внутри КАЖДОГО бандла, а не внутри приложения.
#
# Как звать:
#   Tools/check_bundle_languages.sh build/Togo.xcarchive
#   Tools/check_bundle_languages.sh build/dd/Build/Products/Debug-iphonesimulator/Togo.app
#
# Зачем. 24.09.2026 паспорт архива 216 говорил «языки в .app: fr ru uk —
# внутри бандла, а не по каталогу». Считали в `Togo.app` и не заглянули
# в `PlugIns/`: в `TogoWidgetsExtension.appex` не было ни одной `.lproj`.
# Француз и украинец видели русский на экране блокировки — там, где
# стоят самые короткие и самые заметные строки продукта.
#
# «Внутри бандла» звучит как конец цепочки и им не является, если
# бандлов два. Отсюда правило: проверять ПОСЛЕДНЕЕ звено, а сторожа
# держать на нём, а не на каталоге и не на исходнике.
#
# Зелёный прогон тут не доказательство и сторож на project.pbxproj тоже:
# первый меряет арифметику, второй — объявление цели. Этот скрипт меряет
# то, что уедет в App Store.
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Как звать: Tools/check_bundle_languages.sh <путь к .app или .xcarchive>" >&2
    exit 2
fi

TARGET="$1"

if [ -d "$TARGET/Products/Applications" ]; then
    APP="$(find "$TARGET/Products/Applications" -maxdepth 1 -name '*.app' | head -1)"
elif [ -d "$TARGET" ] && [ "${TARGET##*.}" = "app" ]; then
    APP="$TARGET"
else
    echo "✗ не нашёл .app по пути $TARGET" >&2
    exit 2
fi

[ -n "$APP" ] && [ -d "$APP" ] || { echo "✗ не нашёл .app внутри $TARGET" >&2; exit 2; }

# Языки — по папкам `.lproj`, а не по CFBundleLocalizations: ключ
# в Info.plist называет обещанное, папки — записанное. И каталог в дереве
# не считается вовсе: он трижды за день оказывался полным при пустом
# экране.
bundle_langs() {
    find "$1" -maxdepth 1 -name '*.lproj' -exec basename {} .lproj \; | sort | tr '\n' ' '
}

APP_LANGS="$(bundle_langs "$APP")"
echo "── $(basename "$APP"): ${APP_LANGS:-НИ ОДНОГО}"

if [ -z "$APP_LANGS" ]; then
    echo "✗ в самом приложении нет ни одной .lproj — считать не от чего." >&2
    exit 1
fi

FAIL=0
FOUND=0

if [ -d "$APP/PlugIns" ]; then
    for EXT in "$APP/PlugIns"/*.appex; do
        [ -d "$EXT" ] || continue
        FOUND=$((FOUND + 1))
        EXT_LANGS="$(bundle_langs "$EXT")"
        echo "── $(basename "$EXT"): ${EXT_LANGS:-НИ ОДНОГО}"
        if [ "$EXT_LANGS" != "$APP_LANGS" ]; then
            # Скобки обязательны: «$APP_LANGS»» bash читает как имя
            # переменной ВМЕСТЕ с закрывающей кавычкой-ёлочкой — байты
            # `»` идут в идентификатор, и при `set -u` скрипт падает
            # «unbound variable» ровно в той ветке, ради которой написан.
            # Поймано на архиве 216 при первом же красном прогоне.
            echo "✗ $(basename "$EXT") несёт «${EXT_LANGS:-ничего}», а приложение «${APP_LANGS}»." >&2
            echo "  Расширение читает СВОЙ бандл: чего нет здесь, человек увидит" >&2
            echo "  по-русски — на экране блокировки, в «острове» и в виджете." >&2
            echo "  Каталог должен лежать в папке, синхронизированной в обе цели" >&2
            echo "  (TogoShared/Resources/), а не у приложения." >&2
            FAIL=1
        fi
    done
fi

# Проверка, которой было что проверять. Скрипт, не нашедший ни одного
# расширения, молчит так же, как тот, у которого всё сошлось, — а у Того
# расширение виджета есть всегда.
if [ "$FOUND" -eq 0 ]; then
    echo "✗ расширений в PlugIns/ не найдено вовсе — проверять было нечего," >&2
    echo "  а у Того есть TogoWidgetsExtension. Либо путь не тот, либо" >&2
    echo "  расширение не вошло в сборку." >&2
    exit 1
fi

[ "$FAIL" -eq 0 ] || exit 1

echo "✓ языки совпадают во всех $((FOUND + 1)) бандлах: $APP_LANGS"
echo "  Чего это НЕ значит: что строки переведены. Совпадение папок .lproj"
echo "  говорит только, что каталог доехал до каждого бандла."
