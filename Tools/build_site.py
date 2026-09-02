# -*- coding: utf-8 -*-
"""
Того · страницы политики и поддержки для App Store.

Apple требует ссылку на политику конфиденциальности отдельным полем —
и для внешнего теста в TestFlight, и для App Review. Ссылка обязана
открываться: мёртвая — это отказ по 5.1.1.

Текст берётся из того же места, что видит человек в приложении,
`Togo/Features/Settings/LegalScreens.swift`. Второй копии нет
намеренно: два текста о приватности, живущие порознь, однажды
разойдутся, и наружу уедет тот, который никто не перечитывал.

    python3 Tools/build_site.py        # соберёт site/

Дальше папку `site/` нужно где-то опубликовать — см. docs/APP-STORE.md.
"""
import html
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "Togo/Features/Settings/LegalScreens.swift")
OUT = os.path.join(ROOT, "site")

# Почта берётся оттуда же, откуда её берёт приложение.
PERSISTENCE = os.path.join(ROOT, "TogoShared/Domain/Persistence.swift")


def contact(name):
    text = open(PERSISTENCE, encoding="utf-8").read()
    match = re.search(r'static let %s = "([^"]+)"' % name, text)
    if not match:
        sys.exit(f"не нашёл Contacts.{name} — поменялся Persistence.swift?")
    return match.group(1)


SUPPORT = contact("support")
PRIVACY = contact("privacy")


def substitute(text):
    """Свифтовая интерполяция в тексте — только про адреса."""
    return (text.replace("\\(Contacts.privacy)", PRIVACY)
                .replace("\\(Contacts.support)", SUPPORT)
                .replace('\\"', '"'))


def extract(screen):
    """Разобрать один LegalDocument(...) из исходника экрана."""
    source = open(SOURCE, encoding="utf-8").read()
    start = source.find(f"struct {screen}: View")
    if start < 0:
        sys.exit(f"в {SOURCE} нет {screen}")
    end = source.find("\nstruct ", start + 1)
    block = source[start:end if end > 0 else len(source)]

    def field(name):
        match = re.search(r'%s: "((?:[^"\\]|\\.)*)"' % name, block)
        return substitute(match.group(1)) if match else None

    sections = []
    for match in re.finditer(r'\.init\(title: "((?:[^"\\]|\\.)*)", body: \[(.*?)\]\)',
                             block, re.S):
        paragraphs = [substitute(p) for p in
                      re.findall(r'"((?:[^"\\]|\\.)*)"', match.group(2))]
        sections.append((substitute(match.group(1)), paragraphs))

    if not sections:
        sys.exit(f"в {screen} не нашлось ни одного раздела — поменялась вёрстка?")

    return {"title": field("title"), "updated": field("updated"),
            "intro": field("intro"), "sections": sections}


PAGE = """<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} — Того</title>
<link rel="stylesheet" href="../_style.css">
</head>
<body>
<main>
<header>
  <div class="name">Того</div>
  <h1>{title}</h1>
  <p class="updated">Обновлено {updated}.</p>
</header>
{body}
<footer>
  <p>Связь: <a href="mailto:{support}">{support}</a> · <a href="../index.html">другие приложения</a></p>
</footer>
</main>
</body>
</html>
"""

SUPPORT_PAGE = """<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Поддержка — Того</title>
<link rel="stylesheet" href="../_style.css">
</head>
<body>
<main>
<header>
  <div class="name">Того</div>
  <h1>Поддержка</h1>
  <p class="updated">Отвечает человек, обычно в течение двух рабочих дней.</p>
</header>

<div class="card">
  <h2>Написать</h2>
  <p><a href="mailto:{support}?subject=Того">{support}</a></p>
  <p>Если пишете про ошибку, приложите версию и сборку — они в «Настройки →
  Версия», их можно выделить и скопировать. И модель телефона с версией iOS.</p>
  <p>Если что-то в приложении мешает ухаживать за собакой — пишите сразу.
  Это важнее новых возможностей.</p>
</div>

<h2>Частые вопросы</h2>

<h3>Почему вердикт говорит «непонятно»?</h3>
<p>Ему нужно 3–4 дня записей, чтобы выучить интервалы. До этого он честно
признаётся, что не знает, и не выдумывает. Кнопка «Вывожу» при этом остаётся
первой во всех исходах: приложение не знает лучше вас.</p>

<h3>Где вкладка «Здоровье»?</h3>
<p>Она приходит вместе с курсом лечения и уходит вместе с ним: включается
в профиле собаки, выключается кнопкой «Курс завершён» внизу «Здоровья».
Записи при этом остаются в истории и в отчёте врачу.</p>

<h3>Две записи об одном событии</h3>
<p>Если два человека отметили одно и то же в пределах 20 минут, приложение
покажет карточку слияния обоим. Чужое оно молча не перезаписывает.</p>

<h3>Как забрать свои записи</h3>
<p>«Настройки → Данные и приватность» — выгрузка в CSV и удаление всего,
без писем и ожидания. CSV открывается в Numbers и Excel.</p>

<h2>Приложение — не медицинское устройство</h2>
<p>Того не ставит диагнозов и не назначает дозировок. Решения о здоровье
собаки принимаете вы и ваш ветеринар; приложение показывает то, что вы сами
в него записали.</p>

<footer>
  <p><a href="privacy.html">Политика приватности</a> ·
     <a href="terms.html">Условия использования</a> ·
     <a href="../index.html">другие приложения</a></p>
</footer>
</main>
</body>
</html>
"""

def linkify(text):
    """Адрес почты в тексте — ссылка: на странице по нему пишут."""
    for address in (PRIVACY, SUPPORT):
        text = text.replace(address, f'<a href="mailto:{address}">{address}</a>')
    return text


def render(doc):
    parts = []
    if doc["intro"]:
        parts.append('<div class="card">\n  <h2>Коротко</h2>\n  <p>%s</p>\n</div>'
                     % linkify(html.escape(doc["intro"])))
    for title, paragraphs in doc["sections"]:
        parts.append("<h2>%s</h2>" % html.escape(title))
        for paragraph in paragraphs:
            parts.append("<p>%s</p>" % linkify(html.escape(paragraph)))
    return PAGE.format(title=html.escape(doc["title"]),
                       updated=html.escape(doc["updated"]),
                       support=SUPPORT,
                       body="\n".join(parts))


os.makedirs(OUT, exist_ok=True)

for screen, name in (("PrivacyPolicyScreen", "privacy.html"),
                     ("TermsScreen", "terms.html")):
    doc = extract(screen)
    open(os.path.join(OUT, name), "w", encoding="utf-8").write(render(doc))
    print(f"→ site/{name}  ({len(doc['sections'])} разделов)")

open(os.path.join(OUT, "support.html"), "w", encoding="utf-8").write(
    SUPPORT_PAGE.format(support=SUPPORT))
print("→ site/support.html")
