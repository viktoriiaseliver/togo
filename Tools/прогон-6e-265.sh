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

КОММИТ="${1:?первым аргументом — коммит, у числа должен быть адрес}"
СЕССИЯ="6e"
PID=$$
ИМЯ="togo-${СЕССИЯ}-${PID}"
WT="/tmp/${ИМЯ}"
DD="/tmp/${СЕССИЯ}-dd/dd-${СЕССИЯ}-${PID}"   # ВНЕ worktree
ВЕРШИНА="$(pwd)"
LOG="${ВЕРШИНА}/build/logs/unit-${СЕССИЯ}-265-${PID}.log"
РАНТАЙМ="com.apple.CoreSimulator.SimRuntime.iOS-26-5"
ТИП="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
СИМ="Togo-${СЕССИЯ}-${PID}"

mkdir -p "$(dirname "$LOG")" "$DD"

УСТР="$(xcrun simctl create "$СИМ" "$ТИП" "$РАНТАЙМ")"
xcrun simctl erase "$УСТР"

git worktree add --detach "$WT" "$КОММИТ" >/dev/null

{
  echo "сессия        projects-${СЕССИЯ} (тестировщик №1) · предмет СТЕНД"
  echo "наряд         projects-23: различитель рантайма 26.5"
  echo "коммит        $(git -C "$WT" rev-parse HEAD)"
  echo "коротко       $(git -C "$WT" rev-parse --short HEAD)"
  echo "ГРЯЗНЫХ       $(git -C "$WT" status --porcelain | wc -l | tr -d ' ')"
  echo "worktree      ${WT}"
  echo "DerivedData   ${DD}   <- ВНЕ worktree"
  echo "симулятор     ${УСТР} (${СИМ} · iPhone 17 Pro · iOS 26.5) СОЗДАН и СТЁРТ"
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
  -destination "platform=iOS Simulator,id=${УСТР}" \
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
УНИК_OK=$(grep -ao '✔ Test "[^"]*"' "$LOG" | sort -u | wc -l | tr -d ' ')
УНИК_FAIL=$(grep -ao '✘ Test "[^"]*"' "$LOG" | sort -u | wc -l | tr -d ' ')
ВЫПОЛНЕНО=$(( УНИК_OK + УНИК_FAIL ))

echo "лог                 ${LOG}"
echo "коммит              ${КОММИТ}"
echo "rc самого xcodebuild ${RC}"
echo
echo "--- СОСТОЯЛАСЬ ЛИ УСТАНОВКА (это печатается ПЕРВЫМ нарочно) ---"
echo "failed to install   $(grep -aic 'failed to install' "$LOG")"
echo "locate promise      $(grep -aic 'Failed to locate promise' "$LOG")"
echo "Placeholder/UUID    $(grep -aic 'Placeholder did not exist' "$LOG")"
echo "ВЫПОЛНЕНО (уник)    ${ВЫПОЛНЕНО}  при пороге 800   (✔${УНИК_OK} ✘${УНИК_FAIL})"
echo "строка итога        $(grep -ao 'Test run with [0-9]* tests in [0-9]* suites [a-z]*' "$LOG" | tail -1)"
echo
echo "--- ПРИЗНАКИ СТЕНДА ---"
echo "No eligible connection  $(grep -aFc 'No eligible connection available' "$LOG")"
echo "Terminating app         $(grep -aFc 'Terminating app due to uncaught' "$LOG")"
echo "libc++abi               $(grep -aFc 'libc++abi' "$LOG")"
echo "caught                  $(grep -aFc 'caught' "$LOG")"
echo "Restarting              $(grep -aFc 'Restarting after unexpected exit' "$LOG")"
echo "маркеры                 SUCCEEDED $(grep -aFc '** TEST SUCCEEDED **' "$LOG") · FAILED $(grep -aFc '** TEST FAILED **' "$LOG") · EXECUTE FAILED $(grep -aFc '** TEST EXECUTE FAILED **' "$LOG")"
echo "ошибки компиляции       $(grep -acE '^[^ ]+:[0-9]+:[0-9]+: error: ' "$LOG")"
echo
echo "--- упавшие ИМЕНА (уникальные) ---"
grep -ao '✘ Test "[^"]*"' "$LOG" | sort -u

cd "$ВЕРШИНА"
xcrun simctl shutdown "$УСТР" 2>/dev/null || true
xcrun simctl delete "$УСТР" 2>/dev/null || true
git worktree remove --force "$WT" 2>/dev/null || true

# Код возврата — САМОГО xcodebuild, и последней строкой, а не печатью.
exit $RC
