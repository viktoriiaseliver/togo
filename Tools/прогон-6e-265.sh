#!/bin/bash
# Прогон модульного набора на рантайме iOS 26.5 — различитель последнего
# живого кандидата механизма `No eligible connection available`.
#
# Наряд projects-23, тестировщик projects-6e (№1, предмет — стенд).
#
# ЧТО ЭТОТ ПРОГОН ОТВЕЧАЕТ, И ЧТО НЕТ
#
#   ноль исключений ПРИ ВЫПОЛНЕННЫХ ТЕСТАХ   → кандидат «рантайм 27.0»
#                                              ПОДТВЕРЖДЁН
#   те же исключения                         → рантайм ни при чём,
#                                              кандидатов не остаётся
#   ноль исключений ПРИ НУЛЕ ТЕСТОВ          → ЗАМЕР НЕ СОСТОЯЛСЯ.
#                                              Ровно это случилось 08.10:
#                                              установка не началась вовсе
#                                              (Simulator device failed to
#                                              install · Failed to locate
#                                              promise), и ноль прочли
#                                              как «рантайм ни при чём»
#
# Поэтому ПЕРВЫМ печатается «состоялась ли установка», а не число
# исключений: ложная пустота здесь даёт вывод, обратный правде.
#
# ЧЕГО ЗДЕСЬ НЕТ НАРОЧНО
#
#   конвейера на вызове   `скрипт | tail` отдаёт код tail. За эту смену
#                         на этом сгорели ЧЕТВЕРО из четырёх, включая
#                         меня — в замере, следующем за письмом, где
#                         я сам об этом предупреждал
#   trap последним        он перехватывает код возврата; откатывать
#                         нечего — мерим коммит в своём worktree
#   `Cannot use staged migration` в признаках
#                         путь ошибки `…/tmp/togo-migration-<UUID>/`
#                         создаёт САМ ТЕСТ на этом же прогоне (замер a5),
#                         и 17 вхождений пришли на СТЁРТОМ симуляторе
#                         (мой замер). `erase` этого не лечит
#                         по устройству — признаком быть не может
#   якоря `^` в счёте имён
#                         `^✔ Test ` ловит САМУ СТРОКУ ИТОГА и теряет
#                         записи в склеенном логе: `XCTestOutpu✔ Test "…"`.
#                         Верно `✔ Test "` — без якоря, с кавычкой
#   счёта по строке итога
#                         она НЕДОСЧИТЫВАЕТ при перезапусках (сводит
#                         тотали переживших сюит) и расходится
#                         с поимённым выводом внутри одного лога:
#                         107↔103 и 18↔3 измерены. Порог сверяем
#                         УНИКАЛЬНЫМИ именами
#   DerivedData внутри worktree
#                         тогда критерий «грязных 0» недостижим
#                         по устройству: замер сам делает дерево грязным
set -u
set -o pipefail

COMMIT="${1:?первым аргументом — коммит, у числа должен быть адрес}"
SESSION="6e"
PID=$$
WTNAME="togo-${SESSION}-${PID}"
WT="/tmp/${WTNAME}"
DD="/tmp/${SESSION}-dd/dd-${SESSION}-${PID}"   # ВНЕ worktree
ROOT="$(pwd)"
LOG="${ROOT}/build/logs/unit-${SESSION}-265-${PID}.log"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-26-5"
DEVTYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
SIMNAME="Togo-${SESSION}-${PID}"

mkdir -p "$(dirname "$LOG")" "$DD"

UDID="$(xcrun simctl create "$SIMNAME" "$DEVTYPE" "$RUNTIME")"
xcrun simctl erase "$UDID"

git worktree add --detach "$WT" "$COMMIT" >/dev/null

{
  echo "сессия        projects-${SESSION} (тестировщик №1) · предмет СТЕНД"
  echo "наряд         projects-23: различитель рантайма 26.5"
  echo "коммит        $(git -C "$WT" rev-parse HEAD)"
  echo "коротко       $(git -C "$WT" rev-parse --short HEAD)"
  echo "ГРЯЗНЫХ       $(git -C "$WT" status --porcelain | wc -l | tr -d ' ')"
  echo "worktree      ${WT}"
  echo "DerivedData   ${DD}   <- ВНЕ worktree"
  echo "симулятор     ${UDID} (${SIMNAME} · iPhone 17 Pro · iOS 26.5) СОЗДАН и СТЁРТ"
  echo "предмет       -only-testing:TogoTests — единственный модульный таргет"
  echo "ЗАГРУЗКА В НАЧАЛЕ  $(sysctl -n vm.loadavg) · простой ЦП $(top -l 1 -n 0 | awk '/CPU usage/{print $7}')"
  echo "swap          $(sysctl -n vm.swapusage)"
  echo "чужих xcodebuild  $(pgrep -x xcodebuild | wc -l | tr -d ' ')"
  echo "начало        $(date '+%Y-%m-%d %H:%M:%S')"
  echo "==================================================================="
} > "$LOG"

cd "$WT"
xcodebuild test \
  -project Togo.xcodeproj -scheme Togo \
  -destination "platform=iOS Simulator,id=${UDID}" \
  -derivedDataPath "$DD" \
  -only-testing:TogoTests >> "$LOG" 2>&1
RC=$?

{
  echo "==================================================================="
  echo "ЗАГРУЗКА В КОНЦЕ   $(sysctl -n vm.loadavg) · простой ЦП $(top -l 1 -n 0 | awk '/CPU usage/{print $7}')"
  echo "swap          $(sysctl -n vm.swapusage)"
  echo "конец         $(date '+%Y-%m-%d %H:%M:%S')"
  echo "=== rc=${RC} ==="
} >> "$LOG"

# --- приёмка печатается ЗДЕСЬ, а не вспоминается потом ---
UNIQ_OK=$(grep -ao '✔ Test "[^"]*"' "$LOG" | sort -u | wc -l | tr -d ' ')
UNIQ_FAIL=$(grep -ao '✘ Test "[^"]*"' "$LOG" | sort -u | wc -l | tr -d ' ')
DONE=$(( UNIQ_OK + UNIQ_FAIL ))

echo "лог                 ${LOG}"
echo "коммит              ${COMMIT}"
echo "rc самого xcodebuild ${RC}"
echo
echo "--- СОСТОЯЛАСЬ ЛИ УСТАНОВКА (это печатается ПЕРВЫМ нарочно) ---"
echo "failed to install   $(grep -aic 'failed to install' "$LOG")"
echo "locate promise      $(grep -aic 'Failed to locate promise' "$LOG")"
echo "Placeholder/UUID    $(grep -aic 'Placeholder did not exist' "$LOG")"
echo "ВЫПОЛНЕНО (уник)    ${DONE}  при пороге 800   (✔${UNIQ_OK} ✘${UNIQ_FAIL})"
echo "строка итога        $(grep -ao 'Test run with [0-9]* tests in [0-9]* suites [a-z]*' "$LOG" | tail -1)"
echo
echo "--- ПРИЗНАКИ СТЕНДА ---"
echo "No eligible connection  $(grep -aFc 'No eligible connection available' "$LOG")"
echo "Terminating app         $(grep -aFc 'Terminating app due to uncaught' "$LOG")"
echo "libc++abi               $(grep -aFc 'libc++abi' "$LOG")"
echo "caught                  $(grep -aFc 'caught' "$LOG")"
echo "Restarting              $(grep -aFc 'Restarting after unexpected exit' "$LOG")"
echo "маркеры                 SUCCEEDED $(grep -aFc '** TEST SUCCEEDED **' "$LOG") · FAILED $(grep -aFc '** TEST FAILED **' "$LOG") · EXECUTE FAILED $(grep -aFc '** TEST EXECUTE FAILED **' "$LOG")"
echo
echo "--- ОШИБКИ: ТРИ ФОРМЫ РАЗДЕЛЬНО (замер projects-53) ---"
# Адресная форма ловит дефект кода и НЕ ЛОВИТ отказ инструмента:
# он приходит как `<unknown>:0: error: error opening input file`,
# где номер ОДИН, а не два, и шаблон мимо. Проверено на пробе:
# адресный шаблон даёт 0 на строке <unknown>.
#
# Ноль по адресной при НЕнулевой <unknown> значит «инструмент
# не состоялся», а не «ошибок нет». Это обратная сторона уже
# записанного `grep -c "error:"` → 1921 при нуле настоящих: там
# шаблон слишком широк, здесь слишком узок, и узкий опаснее —
# он молчит.
echo "адресных файл:стр:стлб  $(grep -acE '^[^ ]+:[0-9]+:[0-9]+: error: ' "$LOG")"
echo "<unknown> (отказ инстр.) $(grep -acE '^<unknown>:[0-9]*: error: ' "$LOG")"
echo "всех 'error:' (шум)     $(grep -aFc 'error:' "$LOG")   <- на живых логах 33-142 при нуле настоящих"
echo
echo "--- АРТЕФАКТ: решающий ОДИН, и это .xctestrun (замер 53 и 95) ---"
# Правило свода опирается на пару «.xctestrun + Runner.app», но
# на УПАВШЕЙ сборке Runner.app и Togo.app лежат ОБА — половина пары
# ненадёжна. Решает .xctestrun.
echo ".xctestrun              $(ls "$DD"/Build/Products/*.xctestrun 2>/dev/null | wc -l | tr -d ' ')"
echo "объём работы (95)       SwiftCompile $(grep -aFc 'SwiftCompile' "$LOG") · CodeSign $(grep -aFc 'CodeSign' "$LOG")"
echo "   <- «быстро и зелено» неотличимо от «ничего не собралось»;"
echo "      различает ОБЪЁМ, а не код возврата"
echo
echo "--- упавшие ИМЕНА (уникальные) ---"
grep -ao '✘ Test "[^"]*"' "$LOG" | sort -u

cd "$ROOT"
xcrun simctl shutdown "$UDID" 2>/dev/null || true
xcrun simctl delete "$UDID" 2>/dev/null || true
git worktree remove --force "$WT" 2>/dev/null || true

# Код возврата — САМОГО xcodebuild, и последней строкой, а не печатью.
exit $RC
