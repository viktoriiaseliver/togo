#!/bin/bash
# Выкладывает схему общего дневника в CloudKit.
#
# Зачем: в отладке типы записей CloudKit заводит сам, при первой же
# отправке. В production — не заводит: там схему выкладывают явно.
# Без этого шага обмен в TestFlight молча не работает — записи уходят
# в никуда с ошибкой «unknown record type».
#
# Один раз нужен токен управления:
#   1. https://icloud.developer.apple.com/dashboard → Settings → Tokens
#   2. Create Management Token, скопировать
#   3. xcrun cktool save-token --type management
#
# Потом:
#   Tools/deploy_cloudkit_schema.sh
#
# ВАЖНО: последний шаг делается руками, и это не забывчивость.
# Раньше здесь стояло `cktool deploy-schema-changes` — такой команды
# у cktool нет вовсе, и скрипт падал ровно на том шаге, ради которого
# его и писали. Прямой импорт в production CloudKit тоже запрещает:
# «endpoint not applicable in the environment production». Перенос
# development → production делается только кнопкой в дашборде.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONTAINER="${CONTAINER:-iCloud.app.togo.diary}"
TEAM="${TEAM:-L7CPH7W5QW}"

echo "Контейнер: $CONTAINER"

echo "→ импорт схемы в development"
xcrun cktool import-schema \
    --team-id "$TEAM" \
    --container-id "$CONTAINER" \
    --environment development \
    --validate \
    --file CloudKit/schema.ckdb

echo "→ проверяю production"
PRODUCTION="$(xcrun cktool export-schema \
    --team-id "$TEAM" \
    --container-id "$CONTAINER" \
    --environment production)"

MISSING=()
for TYPE in LogEvent DoseRecord; do
    grep -q "RECORD TYPE $TYPE " <<<"$PRODUCTION" || MISSING+=("$TYPE")
done

if [ ${#MISSING[@]} -eq 0 ]; then
    echo
    echo "Готово. В production есть LogEvent и DoseRecord —"
    echo "общий дневник в TestFlight работает."
    exit 0
fi

cat <<NOTE

Схема в development обновлена, но в production её ещё нет:
не хватает ${MISSING[*]}.

Перенести development → production умеет только дашборд — у cktool
такой команды нет, а прямой импорт в production CloudKit запрещает.
Одна кнопка, один раз:

  1. https://icloud.developer.apple.com/dashboard
  2. Контейнер $CONTAINER → Schema
  3. «Deploy Schema Changes…» → Deploy

Потом запусти этот скрипт снова — он проверит и скажет, что готово.

Пока перенос не сделан, общий дневник в TestFlight молчит: записи
уходят с ошибкой «unknown record type», и человеку это видно как
«у второго телефона ничего не появилось».
NOTE
exit 1
