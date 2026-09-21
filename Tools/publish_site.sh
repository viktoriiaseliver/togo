#!/bin/bash
# Кладёт страницы Того в общий сайт приложений и публикует его.
#
#   Tools/publish_site.sh
#
# Apple требует ссылку на политику отдельным полем — и для внешнего теста
# в TestFlight, и для App Review. Ссылка обязана открываться: мёртвая —
# это отказ по 5.1.1, а не придирка.
#
# Сайт общий на все приложения и живёт отдельным репозиторием
# (`~/Projects/site`): у каждого приложения своя папка, стиль один.
# Того занимает `togo/`, соседние папки не трогаются.
#
# Чтобы страницы стали публичными, репозиторий должен уехать на GitHub:
#
#   github.com/new → имя ровно `viktoriiaseliver.github.io`, Public,
#   без README. У репозитория с таким именем Pages включаются сами.
#
# Скрипт сам добавит remote и запушит, когда репозиторий появится.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SITE="${SITE:-$HOME/Projects/site}"
SLUG="${SLUG:-togo}"
REMOTE="${SITE_REMOTE:-git@github.com:viktoriiaseliver/viktoriiaseliver.github.io.git}"

[ -d "$SITE/.git" ] || { echo "✗ нет репозитория сайта: $SITE"; exit 1; }

echo "── собираю страницы"
python3 Tools/build_site.py

echo "── кладу в $SITE/$SLUG"
mkdir -p "$SITE/$SLUG"
# Рекурсивно: с тех пор как страницы стали двуязычными, у них есть
# подпапки `ru/` и `en/`, а `cp site/*.html` брал только корень —
# наружу уезжала развилка без самих страниц, и по коду 200 это было
# незаметно. Соседние папки приложений не трогаются: копируется
# только содержимое site/ в site/$SLUG/.
cp -R site/. "$SITE/$SLUG/"

cd "$SITE"
if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git commit -q -m "Того: политика, условия и поддержка"
    echo "── записано в историю сайта"
else
    echo "── страницы не менялись"
fi

if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin "$REMOTE"
    echo "── remote добавлен"
fi

if git push -q origin HEAD 2>/dev/null; then
    echo "── опубликовано"
else
    cat <<NOTE

✗ Запушить не удалось — скорее всего репозитория ещё нет.

Заведи его один раз:
  1. github.com/new
  2. имя ровно: viktoriiaseliver.github.io
  3. Public, без README
  4. Create repository

Потом запусти эту команду снова.
NOTE
    exit 1
fi

cat <<NOTE

Страницы (адрес без языка сам уводит на язык браузера):
  https://viktoriiaseliver.github.io/$SLUG/privacy.html
  https://viktoriiaseliver.github.io/$SLUG/support.html
  https://viktoriiaseliver.github.io/$SLUG/terms.html

  https://viktoriiaseliver.github.io/$SLUG/en/privacy.html
  https://viktoriiaseliver.github.io/$SLUG/ru/privacy.html

Первая публикация поднимается пару минут. Когда откроются — впиши их
в fastlane/metadata/ru/privacy_url.txt и support_url.txt и выполни
make beta — он проставит политику в TestFlight.
NOTE
