#!/bin/bash
#
# Конвейер сборки для TestFlight, который ФИЗИЧЕСКИ НЕ МОЖЕТ ЗАЛИТЬ.
#
#   bash Tools/сборка-для-testflight.sh                 собрать и замерить
#   bash Tools/сборка-для-testflight.sh --только-замерить [путь]
#   bash Tools/сборка-для-testflight.sh --перезаписать   согласие стереть чужой архив
#
# В этом файле нет ни одного вызова выгрузки — ни `altool`, ни
# `notarytool`, ни `upload_testflight.sh`. Это не дисциплина, а
# устройство: **невозможность надёжнее дисциплины.** 23.09.2026 сессия
# Gamut трижды дошла до подписанного `.ipa` и остановилась сама — не
# «решила не отправлять», а не могла. Заливает человек, руками,
# Tools/upload_testflight.sh, и это отдельное решение.
#
# Конвейер ничего не изобретает: он сцепляет то, что в проекте уже есть
# (`make archive`, `check_bundle_languages.sh`, `check_storefront_languages.py`,
# `archive_fingerprint.sh`) и добавляет к ним то, чего не было —
# проверку чистоты дерева вслух, отказ затирать чужой артефакт
# и печать всего числом.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

ARCH="build/Togo.xcarchive"
MEASURE_ONLY=0
OVERWRITE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --только-замерить) MEASURE_ONLY=1; [ -n "${2:-}" ] && [ "${2:0:2}" != "--" ] && { ARCH="$2"; shift; } ;;
        --перезаписать)    OVERWRITE=1 ;;
        *) echo "не знаю ключа: $1"; exit 2 ;;
    esac
    shift
done

G="git --no-optional-locks"
warns=0
warn() { echo "   ⚠ $1"; warns=$((warns+1)); }

echo "═══ 1. ДЕРЕВО ═══"
# xcodebuild архивирует ДИСК, а не коммит. Поэтому чистота — не формальность:
# незакоммиченная правка уедет в сборку, и отпечаток её не объяснит.
HEAD_HASH=$($G rev-parse --short HEAD)
echo "   HEAD        : $HEAD_HASH  $($G log -1 --format='%ad %s' --date=format:'%d.%m %H:%M' | cut -c1-70)"
DIRTY=$($G status --porcelain | wc -l | tr -d ' ')
echo "   незакоммичено: $DIRTY"
if [ "$DIRTY" != "0" ]; then
    $G status --porcelain | head -10 | sed 's/^/      /'
    warn "дерево ГРЯЗНОЕ — архив будет собран с диска, а не с коммита $HEAD_HASH"
fi
# Спрашиваем ДОСТИЖИМОСТЬ коммита в origin, а не «сколько впереди
# апстрима». Второе было производной от первого и ломалось там, где
# мы теперь собираем всегда.
#
# Замерено 07.10.2026: прежняя строка звала
# `rev-list --count '@{upstream}'..HEAD`, а в worktree на названном
# коммите ВЕТКИ НЕТ — `fatal: HEAD does not point to a branch`. Дальше
# `|| echo '?'` превращало отказ в значение, условие `!= "0"` их
# не отличало, и предупреждение «коммитов нет на origin» печаталось
# при КАЖДОЙ правильной сборке.
#
# > **Отказ инструмента был напечатан как находка о мире.** `?`
# > не сообщает, что замер не состоялся, и читается как факт — тот же
# > класс, что `plutil`, отдавший длину массива вместо значения.
#
# Почему это не косметика: «мерить коммит в worktree» мы только что
# ввели обязательным порядком. Значит ложное предупреждение встало
# бы в каждую верную сборку — а ложное срабатывание не остаётся шумом,
# оно поднимает допуск: рядом живёт `дерево ГРЯЗНОЕ` про то же место
# отчёта, и пролистываться начнут оба. Строку про `ivar` мы полгода
# читали как шум, а потом прочли как причину.
#
# Три состояния, а не два: третье — «ответить нечем», и его нельзя
# сводить ни к «да», ни к «нет».
if ! $G rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    echo "   коммит в origin: ОТВЕТИТЬ НЕЧЕМ — ссылки origin/main нет"
    warn "достижимость не проверена: это НЕ «коммит есть» и НЕ «коммита нет»"
elif $G merge-base --is-ancestor HEAD origin/main 2>/dev/null; then
    echo "   коммит в origin: да ($HEAD_HASH достижим из origin/main)"
else
    AHEAD=$($G rev-list --count origin/main..HEAD 2>/dev/null || echo '?')
    echo "   коммит в origin: НЕТ (своих коммитов поверх origin/main: $AHEAD)"
    warn "коммита нет на origin — сборку не из чего воспроизвести у другого"
fi
[ -e .git/index.lock ] && warn "в .git лежит index.lock"

if [ "$MEASURE_ONLY" = "0" ]; then
    echo
    echo "═══ 2. АРХИВ ═══"
    # Полный цикл стирает чужую работу: у Togo это уже стоило готового
    # архива 189, и остановил тогда таймаут оболочки, а не проверка.
    if [ -d "$ARCH" ] && [ "$OVERWRITE" = "0" ]; then
        echo "   архив уже есть: $ARCH"
        echo "   собран: $(stat -f '%Sm' -t '%d.%m %H:%M' "$ARCH")"
        BUILDNO=$(plutil -extract ApplicationProperties.CFBundleVersion raw "$ARCH/Info.plist" 2>/dev/null)
        echo "   номер в нём: ${BUILDNO:-прочитать не удалось}"
        echo
        echo "   ОСТАНОВЛЕН. Пересборка сотрёт его, а он может быть чужим."
        echo "   Замерить этот:   bash Tools/сборка-для-testflight.sh --только-замерить"
        echo "   Стереть и собрать: bash Tools/сборка-для-testflight.sh --перезаписать"
        exit 3
    fi
    # НЕ в /var/folders/…/T/ — системный временный чистится, и архив
    # исчезает между сборкой и разговором о ней.
    case "$(cd "$(dirname "$ARCH")" && pwd)" in
        /var/folders/*|/tmp/*) echo "   путь во временном каталоге — архив переживёт не всякую ночь"; exit 2 ;;
    esac
    echo "   путь: $ARCH (переживает перезагрузку)"
    echo "   собираю через make archive — номер сборки оттуда же, из числа коммитов…"
    if ! make archive; then
        echo
        echo "   СБОРКА НЕ ПРОШЛА. Числа ниже снимать не с чего."
        exit 1
    fi
fi

[ -d "$ARCH" ] || { echo "архива нет: $ARCH"; exit 2; }
APP=$(ls -d "$ARCH"/Products/Applications/*.app 2>/dev/null | head -1)
[ -n "$APP" ] || { echo "в архиве нет .app"; exit 2; }

echo
echo "═══ 3. ОТПЕЧАТОК ═══"
# «Сборка N собрана из коммита X» — утверждение без основания, пока его
# нечем проверить. Отпечаток превращает «та ли сборка» в вопрос с ответом.
# Вывод через ФАЙЛ, а не через конвейер в `sed`. Прежняя редакция
# писала `bash … | sed 's/^/   /'`, и код возврата брался у `sed` —
# то есть всегда ноль. У нас это записано дважды («код возврата
# берётся у конвейера, а не у команды» и «напечатать код и вернуть
# его — разные действия»), и здесь оба правила обходились разом:
# отпечаток ещё и сам возвращал ноль при расхождении номера.
#
# Повод живой: 07.10.2026 в общей `build/` лежал архив от 28.09
# со сборкой 271 при номере 273 — отпечаток это печатал, и ничто
# не останавливалось.
if [ -f Tools/archive_fingerprint.sh ]; then
    FP_LOG=$(mktemp)
    bash Tools/archive_fingerprint.sh "$ARCH" >"$FP_LOG" 2>&1
    FP_RC=$?
    sed 's/^/   /' "$FP_LOG"
    rm -f "$FP_LOG"
    if [ $FP_RC -eq 3 ]; then
        echo
        echo "   ОСТАНОВ: номер архива не тот, который собираемся отдать."
        echo "   Это не предупреждение, а отказ: выгрузка отдала бы чужую"
        echo "   сборку, а ASC либо принял бы её, либо отказал по занятому"
        echo "   номеру — и второе мы узнали бы последними."
        echo "   Собери архив заново (make archive) или сверь"
        echo "   Tools/номер-сборки.txt с тем, что уже в ASC."
        exit 3
    fi
    if [ $FP_RC -ne 0 ]; then
        echo "   Отпечаток вернул код $FP_RC — снять не удалось, это не «сошлось»."
        exit $FP_RC
    fi
else
    echo "   Tools/archive_fingerprint.sh нет — отпечаток снять нечем"
fi

echo
echo "═══ 4. НОМЕР И ВЕРСИЯ — ИЗ Info.plist АРХИВА ═══"
# Не из аргумента скрипта и не из Makefile: аргумент говорит, что
# ПРОСИЛИ, а plist — что ПОЛУЧИЛОСЬ.
for k in CFBundleShortVersionString CFBundleVersion; do
    v=$(plutil -extract "ApplicationProperties.$k" raw "$ARCH/Info.plist" 2>/dev/null)
    printf '   %-28s %s\n' "$k" "${v:-прочитать не удалось}"
done
printf '   %-28s %s\n' "собран" "$(stat -f '%Sm' -t '%d.%m.%Y %H:%M' "$ARCH")"
printf '   %-28s %s\n' "коммитов в HEAD сейчас" "$($G rev-list --count HEAD)"

echo
echo "═══ 5. ЯЗЫКИ В БАНДЛАХ ЭТОГО АРХИВА ═══"
# Не по каталогу: каталог говорит о намерении, бандл — о том, что уедет.
# И в КАЖДОМ бандле, включая PlugIns/*.appex.
if [ -f Tools/check_bundle_languages.sh ]; then
    bash Tools/check_bundle_languages.sh "$ARCH" 2>&1 | sed 's/^/   /' || warn "счёт языков дал отказ"
fi
if [ -f Tools/check_storefront_languages.py ]; then
    python3 Tools/check_storefront_languages.py "$APP" 2>&1 | sed 's/^/   /' || warn "языки витрины расходятся с бинарником"
fi

echo
echo "═══ 6. СОСТОЯНИЕ ВЫГРУЗКИ ═══"
echo "   Этот конвейер НЕ УМЕЕТ заливать. В нём нет вызовов altool и notarytool."
if [ -z "${ASC_ISSUER:-}${ASC_ISSUER_ID:-}" ]; then
    echo "   ASC_ISSUER в окружении нет — выгрузка невозможна, а не запрещена."
else
    echo "   ASC_ISSUER в окружении есть — но заливать этот скрипт всё равно не станет."
fi
echo "   Заливает человек: Tools/upload_testflight.sh"
echo "   После заливки ОТДЕЛЬНЫМ шагом нужна привязка к версии:"
echo "     PATCH /v1/appStoreVersions/{id}/relationships/build"
echo "   Она не следует ни из заливки, ни из раздачи. 05.10 у Timer было"
echo "   219 залито и 134 привязано."
echo "   Раздача группам этим ключом ASC не закрывается: betaGroups и"
echo "   betaTesters отвечают 403 — руками в App Store Connect."
echo "   Тестировщику: приложение УДАЛИТЬ, потом ставить из TestFlight."
echo "   Поверх дневной сборки база не откроется, и он будет прав, решив,"
echo "   что сборка сломана."

echo
if [ "$warns" = "0" ]; then
    echo "═══ ИТОГ: замечаний нет ═══"
else
    echo "═══ ИТОГ: замечаний $warns — выше со значком ⚠ ═══"
fi
exit 0
