#!/bin/bash
# Публикует страницы политики и поддержки на GitHub Pages.
#
#   Tools/publish_site.sh
#
# Apple требует ссылку на политику отдельным полем — и для внешнего теста
# в TestFlight, и для App Review. Ссылка обязана открываться: мёртвая —
# это отказ по 5.1.1, а не придирка.
#
# Один раз нужно завести публичный репозиторий сайта:
#
#   github.com/new → имя ровно `viktoriiaseliver.github.io`,
#   Public, без README. Больше ничего делать не надо:
#   у репозитория с таким именем Pages включаются сами.
#
# Дальше эта команда собирает страницы из исходников приложения
# и кладёт их в папку `togo/` того репозитория. Соседние папки
# (например `timer/`) не трогаются — у каждого приложения своя.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SITE_REPO="${SITE_REPO:-git@github.com:viktoriiaseliver/viktoriiaseliver.github.io.git}"
SLUG="${SLUG:-togo}"
WORK="build/site-repo"

echo "── собираю страницы"
python3 Tools/build_site.py

echo "── забираю репозиторий сайта"
rm -rf "$WORK"
if ! git clone --depth 1 "$SITE_REPO" "$WORK" 2>/dev/null; then
    cat <<NOTE
✗ Репозитория сайта нет: $SITE_REPO

Заведи его один раз:
  1. github.com/new
  2. имя ровно: viktoriiaseliver.github.io
  3. Public, без README
  4. Create repository

Потом запусти эту команду снова.
NOTE
    exit 1
fi

echo "── обновляю $SLUG/"
rm -rf "${WORK:?}/$SLUG"
mkdir -p "$WORK/$SLUG"
cp site/*.html "$WORK/$SLUG/"

cd "$WORK"
if git diff --quiet && git diff --cached --quiet && [ -z "$(git status --porcelain)" ]; then
    echo "Страницы не менялись."
else
    git add -A
    git commit -q -m "Того: политика, условия и поддержка"
    git push -q origin HEAD
    echo "── опубликовано"
fi

BASE="https://viktoriiaseliver.github.io/$SLUG"
cat <<NOTE

Страницы:
  $BASE/
  $BASE/privacy.html
  $BASE/terms.html

Первая публикация поднимается пару минут. Когда откроются — впиши их
в fastlane/metadata/ru/privacy_url.txt и support_url.txt и выполни
`make beta`: он проставит политику в TestFlight.
NOTE
