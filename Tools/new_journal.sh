#!/bin/bash
# Заводит запись в журнале проекта за сегодня и вписывает её в оглавление.
#
#   make journal
#
# Журнал — не changelog. Changelog отвечает «что изменилось в приложении»,
# журнал — «что делали, почему именно так и что дальше». Через полгода
# полезнее второе.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATE="$(date +%Y-%m-%d)"
HUMAN="$(date +'%-d %B %Y')"
DIR="$ROOT/docs/journal"
FILE="$DIR/$DATE.md"
INDEX="$ROOT/docs/JOURNAL.md"

mkdir -p "$DIR"

if [ -f "$FILE" ]; then
    echo "Запись за $DATE уже есть: docs/journal/$DATE.md"
    exit 0
fi

cat > "$FILE" <<TEMPLATE
# $HUMAN

## Что сделали

-

## Почему именно так

-

## Что это меняет для человека с собакой

-

## Что дальше и зачем

-

## Открытые вопросы

-
TEMPLATE

# Оглавление держим свежим: новые записи сверху.
if [ ! -f "$INDEX" ]; then
    printf '# Журнал проекта\n\n' > "$INDEX"
fi

python3 - "$INDEX" "$DATE" "$HUMAN" <<'PY'
import sys
index, date, human = sys.argv[1], sys.argv[2], sys.argv[3]
line = "- [%s](journal/%s.md) — \n" % (human, date)
text = open(index, encoding="utf-8").read()
if date in text:
    sys.exit(0)
head, _, tail = text.partition("\n\n")
open(index, "w", encoding="utf-8").write(head + "\n\n" + line + tail)
PY

echo "docs/journal/$DATE.md"
