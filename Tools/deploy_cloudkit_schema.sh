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

# Сверяем не только типы, но и поля.
#
# Раньше здесь проверялось наличие LogEvent и DoseRecord — и скрипт
# говорил «работает», когда в production не было поля medicationName.
# Отметка дозы при этом валила отправку целиком, а тут было написано,
# что всё хорошо. Проверка, которая не краснеет на сломанном, не
# проверяет ничего.
PROD_FILE="$(mktemp)"
printf '%s\n' "$PRODUCTION" > "$PROD_FILE"
MISSING="$(python3 - "$PROD_FILE" CloudKit/schema.ckdb <<'PY'
import re, sys

def parse(path):
    types = {}
    for name, body in re.findall(r'RECORD TYPE (\w+) \((.*?)\)\s*;',
                                 open(path).read(), re.S):
        fields = set()
        for line in body.splitlines():
            line = line.strip().rstrip(',')
            if not line or line.startswith('GRANT'):
                continue
            field = line.split()[0].strip('"')
            if not field.startswith('___'):
                fields.add(field)
        types[name] = fields
    return types

prod, want = parse(sys.argv[1]), parse(sys.argv[2])
gaps = []
for name, fields in sorted(want.items()):
    if name not in prod:
        gaps.append(f"{name} — типа нет вовсе")
        continue
    gaps += [f"{name}.{f}" for f in sorted(fields - prod[name])]
print("\n".join(gaps))
PY
)"
rm -f "$PROD_FILE"

if [ -z "$MISSING" ]; then
    echo
    echo "Готово. В production есть все типы и поля из schema.ckdb —"
    echo "общий дневник в TestFlight работает."
    exit 0
fi

cat <<NOTE

Схема в development обновлена, но в production её ещё нет.
Не хватает:

$MISSING

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
