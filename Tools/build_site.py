# -*- coding: utf-8 -*-
"""
Того · страницы политики и поддержки для App Store.

Apple требует ссылку на политику конфиденциальности отдельным полем —
и для внешнего теста в TestFlight, и для App Review. Ссылка обязана
открываться: мёртвая — это отказ по 5.1.1.

Русский текст берётся из того же места, что видит человек в приложении,
`Togo/Features/Settings/LegalScreens.swift`. Второй копии нет
намеренно: два текста о приватности, живущие порознь, однажды
разойдутся, и наружу уедет тот, который никто не перечитывал.

Английский перевод лежит в `Tools/site_en.py` — и это как раз вторая
копия, потому что в приложении английского пока нет вовсе. Разойтись
молча она не может: здесь считается отпечаток русского текста и
сверяется с записанным рядом с переводом. Не сходится — сборка падает
и говорит, какой раздел поменялся.

Раскладка на выходе (адреса из App Store Connect не меняются):

    site/privacy.html      развилка по языку браузера
    site/ru/privacy.html   русская страница
    site/en/privacy.html   английская

    python3 Tools/build_site.py        # соберёт site/

Дальше папку `site/` нужно где-то опубликовать — см. docs/APP-STORE.md.
"""
import hashlib
import html
import os
import re
import sys

import site_en

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "Togo/Features/Settings/LegalScreens.swift")
OUT = os.path.join(ROOT, "site")

# Почта берётся оттуда же, откуда её берёт приложение.
PERSISTENCE = os.path.join(ROOT, "TogoShared/Domain/Persistence.swift")

# Английский первым: он же x-default, к нему уходит браузер с любым
# третьим языком.
LANGS = ("en", "ru")


def contact(name):
    text = open(PERSISTENCE, encoding="utf-8").read()
    match = re.search(r'static let %s = "([^"]+)"' % name, text)
    if not match:
        sys.exit(f"не нашёл Contacts.{name} — поменялся Persistence.swift?")
    return match.group(1)


SUPPORT = contact("support")
PRIVACY = contact("privacy")


def base_url():
    """Адрес сайта берётся из того же файла, что уходит в App Store Connect.

    Иначе он живёт двумя копиями: одна в витрине, другая в `<link rel=canonical>`,
    и однажды они разойдутся — а расхождение канонической ссылки поисковик
    молча трактует как дубль.
    """
    path = os.path.join(ROOT, "fastlane/metadata/ru/privacy_url.txt")
    url = open(path, encoding="utf-8").read().strip()
    if not url.startswith("http"):
        sys.exit(f"в {path} не адрес: {url!r}")
    return url.rsplit("/", 1)[0]


BASE = base_url()


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


# Подписи вокруг текста. Английские живут вместе с переводом.
LABELS = {
    "ru": {
        "short": "Коротко",
        "updated": "Обновлено",
        "other_apps": "другие приложения",
        "contact": "Связь",
        "privacy": "Политика приватности",
        "terms": "Условия использования",
    },
    "en": site_en.LABELS,
}

NAMES = {"ru": "Того", "en": "Togo"}


def fingerprint(documents):
    """Отпечаток русского текста — чтобы перевод не разошёлся молча.

    Считается по тому, что реально уехало бы на страницу: заголовок,
    дата, «коротко» и все разделы с абзацами. Правка запятой в комментарии
    отпечаток не двигает, правка текста — двигает.
    """
    digest = hashlib.sha256()
    for screen in sorted(documents):
        doc = documents[screen]
        digest.update(screen.encode())
        for part in (doc["title"], doc["updated"], doc["intro"] or ""):
            digest.update(part.encode())
        for title, paragraphs in doc["sections"]:
            digest.update(title.encode())
            for paragraph in paragraphs:
                digest.update(paragraph.encode())
    return digest.hexdigest()[:16]


def check_translation(documents):
    """Свериться с переводом: тот же набор разделов и тот же отпечаток."""
    actual = fingerprint(documents)
    if actual == site_en.SOURCE_FINGERPRINT:
        return

    lines = ["Русский текст в LegalScreens.swift изменился, а перевод",
             "в Tools/site_en.py — нет. Наружу уехала бы английская",
             "страница, которая говорит не то же самое.", ""]
    for screen in sorted(documents):
        russian = documents[screen]["sections"]
        english = site_en.DOCUMENTS.get(screen, {}).get("sections", [])
        if len(russian) != len(english):
            lines.append(f"  {screen}: разделов {len(russian)}, "
                         f"в переводе {len(english)}")
            continue
        for index, ((_, ru_body), (en_title, en_body)) in enumerate(
                zip(russian, english), 1):
            if len(ru_body) != len(en_body):
                lines.append(f"  {screen}, раздел {index} ({en_title}): "
                             f"абзацев {len(ru_body)}, в переводе {len(en_body)}")
    lines += ["",
              "Перечитать перевод, поправить и вписать новый отпечаток:",
              f'  SOURCE_FINGERPRINT = "{actual}"']
    sys.exit("\n".join(lines))


PAGE = """<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} — {name}</title>
<meta name="description" content="{description}">
<link rel="canonical" href="{base}/{lang}/{file}">
{alternates}
<link rel="stylesheet" href="../../style.css">
</head>
<body>
<main>
<header>
  <div class="name">{name}</div>
  <h1>{title}</h1>
  <p class="updated">{updated_label} {updated}.</p>
  <p class="lang">{switcher}</p>
</header>
{body}
<footer>
  <p>{contact_label}: <a href="mailto:{support}">{support}</a> · <a href="../../{lang}/index.html">{other_apps}</a></p>
</footer>
</main>
</body>
</html>
"""

SUPPORT_PAGE = """<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{page_title}</title>
<meta name="description" content="{description}">
<link rel="canonical" href="{base}/{lang}/support.html">
{alternates}
<link rel="stylesheet" href="../../style.css">
</head>
<body>
<main>
<header>
  <div class="name">{name}</div>
  <h1>{title}</h1>
  <p class="updated">{updated}</p>
  <p class="lang">{switcher}</p>
</header>
{body}
<footer>
{footer}
</footer>
</main>
</body>
</html>
"""

# Развилка на старом адресе. Именно он стоит в App Store Connect и
# в fastlane/metadata — менять его нельзя, а языка в нём нет. Скрипт
# в <head> срабатывает до отрисовки; ссылки ниже видит только тот,
# у кого выключен JavaScript, и для него это работающая развилка.
STUB_PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{titles} — Togo · Того</title>
{alternates}
<link rel="stylesheet" href="../style.css">
<script>
(function () {{
  var wanted = navigator.languages || [navigator.language || "en"];
  for (var i = 0; i < wanted.length; i++) {{
    var tag = String(wanted[i]).toLowerCase();
    if (tag.indexOf("ru") === 0) {{ location.replace("ru/{file}"); return; }}
    if (tag.indexOf("en") === 0) {{ location.replace("en/{file}"); return; }}
  }}
  location.replace("en/{file}");
}})();
</script>
</head>
<body>
<main>
<header>
  <div class="name">Togo · Того</div>
  <h1>{en_title}</h1>
  <p class="updated">Choose a language. Выберите язык.</p>
</header>

<p class="lang"><a href="en/{file}">{en_title} — in English</a></p>
<p class="lang"><a href="ru/{file}">{ru_title} — по-русски</a></p>

<footer>
  <p><a href="mailto:{support}">{support}</a></p>
</footer>
</main>
</body>
</html>
"""


def alternates(file):
    """hreflang нужен абсолютными адресами, относительные поисковик не берёт."""
    lines = ['<link rel="alternate" hreflang="%s" href="%s/%s/%s">'
             % (lang, BASE, lang, file) for lang in LANGS]
    lines.append('<link rel="alternate" hreflang="x-default" href="%s/en/%s">'
                 % (BASE, file))
    return "\n".join(lines)


def switcher(lang, file, titles):
    """Переключатель языков: свой язык первым и не ссылкой, остальные — ссылками."""
    parts = ["<strong>%s</strong>" % titles[lang]]
    parts += ['<a href="../%s/%s">%s</a>' % (other, file, titles[other])
              for other in LANGS if other != lang]
    return " · ".join(parts)


LANGUAGE_NAMES = {"ru": "Русский", "en": "English"}


def linkify(text):
    """Адрес почты в тексте — ссылка: на странице по нему пишут.

    Одним проходом и сразу по всем адресам. Раньше здесь стоял цикл
    с `str.replace` на каждый адрес — а `Contacts.privacy`
    и `Contacts.support` это один и тот же ящик. Второй проход находил
    адрес внутри ссылки, собранной первым, и подставлял ссылку в ссылку:

        <a href="mailto:<a href="mailto:…">…</a>">…</a>

    На живой странице политики это была единственная строка, по которой
    ревьюер может кликнуть, и она не открывалась. `re.sub` идёт слева
    направо и свой же результат не перечитывает, поэтому вложиться
    ссылке больше некуда — сколько бы адресов ни совпало.
    """
    addresses = sorted({PRIVACY, SUPPORT}, key=len, reverse=True)
    return re.sub("|".join(re.escape(a) for a in addresses),
                  lambda m: f'<a href="mailto:{m[0]}">{m[0]}</a>', text)


def summary(doc):
    """Строка для поисковой выдачи: то же «коротко», обрезанное по слову.

    Потолок — 155 символов: столько держит выдача, и столько же стоит
    в правилах текстов Five More, чтобы у трёх приложений он был один.
    Обрубить самим и по слову лучше, чем отдать поисковику рубить
    посередине.
    """
    text = doc["intro"] or doc["sections"][0][1][0]
    if len(text) <= 155:
        return text
    return text[:152].rsplit(" ", 1)[0] + "…"


def render(doc, lang, file, titles):
    labels = LABELS[lang]
    parts = []
    if doc["intro"]:
        parts.append('<div class="card">\n  <h2>%s</h2>\n  <p>%s</p>\n</div>'
                     % (labels["short"], linkify(html.escape(doc["intro"]))))
    for title, paragraphs in doc["sections"]:
        parts.append("<h2>%s</h2>" % html.escape(title))
        for paragraph in paragraphs:
            parts.append("<p>%s</p>" % linkify(html.escape(paragraph)))
    return PAGE.format(lang=lang, name=NAMES[lang],
                       title=html.escape(doc["title"]),
                       updated=html.escape(doc["updated"]),
                       updated_label=labels["updated"],
                       description=html.escape(summary(doc), quote=True),
                       alternates=alternates(file),
                       switcher=switcher(lang, file, LANGUAGE_NAMES),
                       base=BASE, file=file,
                       contact_label=labels["contact"],
                       other_apps=labels["other_apps"],
                       support=SUPPORT,
                       body="\n".join(parts))


RU_SUPPORT = {
    "file": "support.html",
    "title": "Поддержка",
    "page_title": "Поддержка — Того, дневник собаки",
    "description": "Как связаться с автором Того и ответы на частые вопросы: почему вердикт говорит «непонятно», где вкладка «Здоровье», как забрать свои записи.",
    "updated": "Отвечает человек, обычно в течение двух рабочих дней.",
    "body": """
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
<p>Она приходит с курсом лечения и уходит с ним: включается в профиле
собаки, выключается кнопкой «Курс завершён» внизу «Здоровья». Записи
остаются в истории и в отчёте врачу.</p>

<h3>Два человека отметили одно и то же</h3>
<p>Если два человека отметили одно и то же в пределах 20 минут, приложение
покажет карточку слияния обоим. Чужое оно молча не перезаписывает.</p>

<h3>Как забрать свои записи</h3>
<p>«Настройки → Данные и приватность» — выгрузка в CSV и удаление всего,
без писем и ожидания. CSV открывается в Numbers и Excel.</p>

<h2>Приложение — не медицинское устройство</h2>
<p>Того не ставит диагнозов и не назначает дозировок. Решения о здоровье
собаки принимаете вы и ваш ветеринар; приложение показывает то, что вы сами
в него записали.</p>
""",
    "footer": """
  <p><a href="privacy.html">Политика приватности</a> ·
     <a href="terms.html">Условия использования</a> ·
     <a href="../../ru/index.html">другие приложения</a></p>
""",
}

SUPPORT_PAGES = {"ru": RU_SUPPORT, "en": site_en.SUPPORT}


def render_support(lang):
    page = SUPPORT_PAGES[lang]
    return SUPPORT_PAGE.format(
        lang=lang, name=NAMES[lang],
        title=page["title"], page_title=page["page_title"],
        description=html.escape(page["description"], quote=True),
        updated=page["updated"],
        alternates=alternates("support.html"),
        switcher=switcher(lang, "support.html", LANGUAGE_NAMES),
        base=BASE,
        body=page["body"].format(support=SUPPORT).strip(),
        footer=page["footer"].strip("\n"))


def render_stub(file, titles):
    return STUB_PAGE.format(
        file=file, alternates=alternates(file),
        titles=" · ".join(titles[lang] for lang in LANGS),
        en_title=titles["en"], ru_title=titles["ru"],
        support=SUPPORT)


SCREENS = (("PrivacyPolicyScreen", "privacy.html"),
           ("TermsScreen", "terms.html"))

documents = {screen: extract(screen) for screen, _ in SCREENS}
check_translation(documents)

for lang in LANGS:
    os.makedirs(os.path.join(OUT, lang), exist_ok=True)

written = []


def write(path, text):
    full = os.path.join(OUT, path)
    open(full, "w", encoding="utf-8").write(text)
    written.append(path)


for screen, file in SCREENS:
    russian = documents[screen]
    english = site_en.DOCUMENTS[screen]
    titles = {"ru": russian["title"], "en": english["title"]}

    write(f"ru/{file}", render(russian, "ru", file, LANGUAGE_NAMES))
    write(f"en/{file}", render(
        {"title": english["title"], "updated": english["updated"],
         "intro": substitute(english["intro"]),
         "sections": [(t, [substitute(p) for p in body])
                      for t, body in english["sections"]]},
        "en", file, LANGUAGE_NAMES))
    write(file, render_stub(file, titles))
    print(f"→ {file}  ({len(russian['sections'])} разделов, ru + en)")

for lang in LANGS:
    write(f"{lang}/support.html", render_support(lang))
write("support.html", render_stub("support.html",
                                  {"ru": RU_SUPPORT["title"],
                                   "en": site_en.SUPPORT["title"]}))
print("→ support.html  (ru + en)")


# Проверка того, что уже написано на диск, а не того, что мы собирались
# написать. Ссылку на почту ревьюер обязан открыть — битая почта это
# отказ по 5.1.1, и однажды она сюда уже уехала: адрес подставился
# внутрь адреса, а по коду 200 это было незаметно.
for name in written:
    page = open(os.path.join(OUT, name), encoding="utf-8").read()
    for broken, what in (('mailto:<', "адрес внутри адреса"),
                         ('href="mailto:"', "пустой mailto"),
                         ('<a href="mailto:' + SUPPORT + '">' + SUPPORT
                          + '</a></a>', "лишний закрывающий тег")):
        if broken in page:
            sys.exit(f"site/{name}: сломанная почта — {what}")
    if "mailto:" not in page:
        sys.exit(f"site/{name}: почты нет вовсе — ревьюеру некуда написать")
print(f"почта кликабельна на всех {len(written)} страницах")
