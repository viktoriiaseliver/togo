#!/bin/bash
#
# Прогон UI-набора, который ВИДИТ САМО ПРИЛОЖЕНИЕ.
#
# Зачем он есть
# =============
# Лог `xcodebuild` для UI-прогона содержит вывод РАННЕРА, а не
# приложения: приложение живёт отдельным процессом, и его `os_log`
# в этот лог не попадает ни строкой. Замерено 08.10.2026 на
# `/tmp/прогон-медслой.log` — 272 строки, и `Togo[` в них НОЛЬ
# вхождений при наблюдённом падении приложения.
#
#     Наблюдение «Critical process Togo crashed in (null)» без единой
#     строки о том, что процесс делал, — это форма без содержания.
#     Пятый такой заход не отличается от первого.
#
# И хуже: эти нули читаются как ответ про мир. В тот вечер по ним
# чуть не сняли живого кандидата — «зеркалирования ноль, значит версия
# опровергнута», — хотя ноль был про лог.
#
#     Ноль от инструмента и ноль про мир снаружи неразличимы.
#     Различает только контроль.
#
# Поэтому здесь контроль встроен: если в логе приложения не оказалось
# самого приложения, прогон объявляется НЕСОСТОЯВШИМСЯ и возвращает
# свой код, а не «тесты прошли».
#
# Чем пользоваться
# ================
#   Tools/прогон-ui.sh TogoUITests/МедслойДороги
#   Tools/прогон-ui.sh TogoUITests/МедслойДороги Togo-мояСессия
#
# Переменные окружения:
#   BEZ_SBORKI=1   прогон без сборки (`test-without-building`)
#
# Имена переменных только латиницей: кириллическое имя в bash
# не заводится вовсе и следующая строка выполняется как ни в чём
# не бывало. Поймано трижды за один день 23.09.2026; держит сторож
# `testShellScriptsHaveNoCyrillicVariables`.
set -uo pipefail

SUITE="${1:-}"
if [ -z "$SUITE" ]; then
    echo "нужен набор: Tools/прогон-ui.sh TogoUITests/<Набор>" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

RUN_ID="$$"
SIM_NAME="${2:-Togo-ui-$RUN_ID}"
OUT_DIR="$ROOT/build/ui-$RUN_ID"
mkdir -p "$OUT_DIR"
RUN_LOG="$OUT_DIR/прогон.log"
APP_LOG="$OUT_DIR/приложение.log"

echo "набор:      $SUITE"
echo "симулятор:  $SIM_NAME"
echo "логи:       $OUT_DIR"

# Загрузка печатается РЯДОМ с результатом, а не вместо него: условие,
# при котором дефект виден (высокая загрузка), и условие, при котором
# замеру можно верить, исключают друг друга — значит число про машину
# обязано стоять в том же отчёте.
echo "загрузка до: $(uptime | sed 's/.*averages: //')"
for name in xcodebuild swift-frontend; do
    # Скобки вокруг имени не ради bash — `$name:` он разбирает верно, —
    # а ради сканера: шаблон «цифра/символ вплотную к имени» краснеет
    # на этой строке ложно, и следующий потратит заход на здоровый код.
    echo "  ${name}: $(pgrep -x "$name" | wc -l | tr -d ' ')"
done

# Своё устройство, а не общее: общее даёт чужое приложение в кадре
# и чужой заход между erase и прогоном.
UDID="$(xcrun simctl list devices | grep -F "$SIM_NAME (" | head -1 \
        | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
if [ -z "$UDID" ]; then
    RUNTIME="$(xcrun simctl list runtimes available \
        | grep -oE 'com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]+' | tail -1)"
    UDID="$(xcrun simctl create "$SIM_NAME" \
        com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro "$RUNTIME")"
    echo "создан:     $UDID"
fi
echo "udid:       $UDID"

xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1

# Ловим вывод САМОГО приложения. Без этого весь прогон бессмыслен:
# именно эта строка отличает инструмент от предыдущего захода.
xcrun simctl spawn "$UDID" log stream \
    --level debug --style compact \
    --predicate 'process == "Togo"' > "$APP_LOG" 2>/dev/null &
STREAM_PID=$!
sleep 2

ACTION="test"
[ "${BEZ_SBORKI:-0}" = "1" ] && ACTION="test-without-building"

xcodebuild -project Togo.xcodeproj -scheme Togo -configuration Debug \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$OUT_DIR/dd" \
    "$ACTION" -only-testing:"$SUITE" > "$RUN_LOG" 2>&1
RC=$?

kill "$STREAM_PID" 2>/dev/null
wait "$STREAM_PID" 2>/dev/null

echo "загрузка после: $(uptime | sed 's/.*averages: //')"

# КОНТРОЛЬ: видно ли в логе само приложение.
#
# Стоит ПОСЛЕ прогона и ДО любого вывода о результате — потому что
# при нуле все числа ниже рассказывают про инструмент, а не про мир,
# и печатать их как результат нельзя.
# Без `|| echo 0` на хвосте: `grep -c` и так печатает ноль, а `|| echo 0`
# добавил бы ВТОРУЮ строку — сравнение ниже сломалось бы об «0\n0».
# Ровно этот приём у нас уже превратил отказ команды в «ноль живых
# сборок» при пятнадцати настоящих.
APP_LINES="$(grep -c 'Togo' "$APP_LOG" 2>/dev/null)"
APP_LINES="${APP_LINES:-0}"
echo "строк приложения в логе: $APP_LINES"
if [ "$APP_LINES" -eq 0 ]; then
    cat >&2 <<'KONEC'

ЗАМЕР НЕ СОСТОЯЛСЯ: в логе приложения нет самого приложения.

Это НЕ «приложение молчало» и НЕ «дефекта нет» — это отказ
инструмента наблюдения. Любое число из такого прогона рассказывает
про оснастку, а не про мир; в частности, «зеркалирования ноль»
отсюда НЕ следует.

Чинить оснастку (поднялся ли симулятор, тот ли процесс в предикате),
а не считать результат.
KONEC
    exit 9
fi

echo "--- итог ---"
grep -E "Test run with|Restarting after unexpected exit|\*\* TEST" "$RUN_LOG" | tail -5
echo "перезапусков: $(grep -c 'Restarting after unexpected exit' "$RUN_LOG")"
echo "--- приложение: признаки смерти ---"
for pattern in 'Terminating app due to uncaught exception' \
               'Critical process' \
               'NSCloudKitMirroringDelegate' \
               'CKAccountStatusNoAccount'; do
    printf '  %-44s %s\n' "$pattern" "$(grep -cF "$pattern" "$APP_LOG")"
done

echo "rc=$RC"
# Код возврата отдаётся последней строкой и именно свой.
# Напечатать код и вернуть его — разные действия: печать видит человек,
# код видит тот, кто решает, зелено ли. И `trap` после этой строки
# ставить нельзя — он перехватит код.
exit $RC
