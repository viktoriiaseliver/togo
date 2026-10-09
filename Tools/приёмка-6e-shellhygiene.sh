#!/bin/bash
# Приёмка сторожа `ShellHygieneTests` ПОДДЕЛКАМИ, а не чтением.
#
# Сторож заведён projects-58 по моей находке (правило свода стояло
# первым и охранялось только в Gamut). Правило я уже прогнал
# на настоящих сломанных данных — своей же прежней редакции из git,
# 9 нарушений из 9 поймано, 55 строк русской прозы молчат.
#
# **Но «регулярка верна» и «сторож краснеет в прогоне» — разные
# утверждения.** Здесь проверяется второе.
#
# ЗАЧЕМ ТРИ ПОДДЕЛКИ, А НЕ ОДНА. Просьба projects-58, и довод его:
# если одна подделка покраснит БОЛЬШЕ ОДНОГО утверждения — значит
# утверждения не независимы, и это надо знать до того, как сторож
# начнёт охранять. Одна подделка показала бы, что сторож краснеет,
# и утверждения выглядели бы взаимозаменяемыми.
#
#   A  кириллица В ИМЕНИ          → обязан краснеть ТОЛЬКО «Имена
#                                   переменных только латиницей»
#   B  многобайтный ВПЛОТНУЮ      → только «К имени не приклеен
#                                   многобайтный символ»
#   C  подстановка без set -u     → только «Скрипт объявляет set -u»
#
# ИЗОЛЯЦИЯ. Подделки живут в отдельном `git worktree` во временном
# каталоге: в общее дерево они не попадают ВОВСЕ. Это сильнее, чем
# предупреждение вслух, — за смену предупреждение трижды не доехало
# до того, кто читает логи.
#
# ОТКАТ в `trap … EXIT INT TERM`, и это не формальность: у projects-58
# откат стоял последней строкой, таймаут убил скрипт посреди подделки C,
# и файл остался лежать. Спасла изоляция worktree, а не trap. Поэтому
# здесь ОБА: trap и worktree.
#
# Имена переменных ЛАТИНИЦЕЙ. За смену я нарушил это правило в своём же
# скрипте — девять имён, прогон не состоялся. `set -u` обязателен:
# без него класс молчит.
set -u
set -o pipefail

ROOT="$(pwd)"
PID=$$
WT="/tmp/togo-6e-hyg-${PID}"
DD="/tmp/6e-dd/hyg-${PID}"          # ВНЕ worktree
LOG="${ROOT}/build/logs/hyg-6e-${PID}.log"
SUITE='TogoTests/ShellHygieneTests'

mkdir -p "$(dirname "$LOG")" "$DD"

cleanup() {
  cd "$ROOT" 2>/dev/null || true
  xcrun simctl shutdown "${UDID:-}" 2>/dev/null || true
  xcrun simctl delete "${UDID:-}" 2>/dev/null || true
  git worktree remove --force "$WT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

UDID="$(xcrun simctl create "Togo-6e-hyg-${PID}" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5)"
xcrun simctl erase "$UDID"

git worktree add --detach "$WT" HEAD >/dev/null
COMMIT="$(git -C "$WT" rev-parse HEAD)"

{
  echo "приёмка       сторож ShellHygieneTests, ПОДДЕЛКАМИ"
  echo "сессия        projects-6e (тестировщик №1)"
  echo "коммит        ${COMMIT}"
  echo "worktree      ${WT}   <- подделки живут ЗДЕСЬ, не в вершине"
  echo "DerivedData   ${DD}   <- вне worktree"
  echo "симулятор     ${UDID} · iOS 26.5 · создан и СТЁРТ"
  echo "рантайм 26.5 нарочно: на 27.0 стенд отказывает (замер 6e, 09.10)"
  echo "==================================================================="
} > "$LOG"

cd "$WT"

# Собираем ОДИН раз. Дальше меняются только .sh — сторож читает их
# с диска в рантайме (`#filePath` → <worktree>/Tools), поэтому
# пересборка не нужна. Между прогонами различается РОВНО подделка.
echo "--- build-for-testing ---" >> "$LOG"
xcodebuild build-for-testing \
  -project Togo.xcodeproj -scheme Togo \
  -destination "platform=iOS Simulator,id=${UDID}" \
  -derivedDataPath "$DD" >> "$LOG" 2>&1
BRC=$?
echo "build rc=${BRC}" >> "$LOG"
if [ "$BRC" -ne 0 ]; then
  echo "СБОРКА НЕ СОСТОЯЛАСЬ, rc=${BRC} — приёмки не было"
  echo "адресных ошибок:  $(grep -acE '^[^ ]+:[0-9]+:[0-9]+: error: ' "$LOG")"
  echo "<unknown>:        $(grep -acE '^<unknown>:[0-9]*: error: ' "$LOG")"
  exit "$BRC"
fi
echo "артефакт .xctestrun: $(ls "$DD"/Build/Products/*.xctestrun 2>/dev/null | wc -l | tr -d ' ')"

# Прогон набора и печать ИМЁН упавших утверждений.
run_case() {
  local label="$1" out="${LOG}.${1}"
  xcodebuild test-without-building \
    -project Togo.xcodeproj -scheme Togo \
    -destination "platform=iOS Simulator,id=${UDID}" \
    -derivedDataPath "$DD" \
    "-only-testing:${SUITE}" > "$out" 2>&1
  local rc=$?
  local started passed failed
  started=$(grep -ao '◇ Test "[^"]*"' "$out" | sort -u | wc -l | tr -d ' ')
  passed=$(grep -ao '✔ Test "[^"]*"' "$out" | sort -u | wc -l | tr -d ' ')
  failed=$(grep -ao '✘ Test "[^"]*"' "$out" | sort -u | wc -l | tr -d ' ')
  echo
  echo "### ${label}   rc=${rc}"
  echo "ЗАПРОШЕНО 1 набор — ВЫБРАНО: $(grep -ac '◇ Suite "Гигиена shell-скриптов"' "$out")  (ноль = фильтр промахнулся)"
  echo "утверждений начато ${started} · зелёных ${passed} · красных ${failed}"
  if [ "$failed" -gt 0 ]; then
    echo "КРАСНЕЕТ:"
    grep -ao '✘ Test "[^"]*"' "$out" | sort -u | sed 's/^/   /'
  fi
  echo "признаки стенда: Restarting $(grep -aFc 'Restarting after unexpected exit' "$out") · Terminating $(grep -aFc 'Terminating app due to uncaught' "$out")"
}

# --- ЗДОРОВЫЙ: прежде подделок, иначе вывод о стороже из прогона,
#     которого не было ---
run_case "ЗДОРОВЫЙ"

# --- A: кириллица В ИМЕНИ ---
printf '#!/bin/bash\nset -u\nПУТЬ="/tmp/a"\necho "$ПУТЬ"\n' > Tools/zz-poddelka-a.sh
run_case "ПОДДЕЛКА-A-кириллица-в-имени"
rm -f Tools/zz-poddelka-a.sh

# --- B: многобайтный символ ВПЛОТНУЮ к латинскому имени ---
printf '#!/bin/bash\nset -u\nprobe="x"\necho "проба «$probe»"\n' > Tools/zz-poddelka-b.sh
run_case "ПОДДЕЛКА-B-многобайтный-вплотную"
rm -f Tools/zz-poddelka-b.sh

# --- C: подстановка переменных БЕЗ set -u ---
printf '#!/bin/bash\nname="x"\necho "$name"\n' > Tools/zz-poddelka-c.sh
run_case "ПОДДЕЛКА-C-без-set-u"
rm -f Tools/zz-poddelka-c.sh

run_case "ЗДОРОВЫЙ-ПОВТОР"

echo
echo "лог сборки: ${LOG}"
echo "логи прогонов: ${LOG}.*"
echo "подделок в вершине: $(ls "${ROOT}"/Tools/zz-poddelka-*.sh 2>/dev/null | wc -l | tr -d ' ')  (обязан быть 0)"
