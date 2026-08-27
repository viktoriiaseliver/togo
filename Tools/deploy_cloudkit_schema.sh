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
    --file CloudKit/schema.ckdb

echo "→ перенос development → production"
xcrun cktool deploy-schema-changes \
    --team-id "$TEAM" \
    --container-id "$CONTAINER" \
    --source-environment development \
    --target-environment production

echo "Готово. Общий дневник в TestFlight заработает."
