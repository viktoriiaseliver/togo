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


PAGE = """<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · Того</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{
    margin: 0 auto; padding: 32px 20px 64px; max-width: 40rem;
    font: 17px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    color: #1c1c1e; background: #fff;
  }}
  @media (prefers-color-scheme: dark) {{
    body {{ color: #f2f2f7; background: #111; }}
    a {{ color: #6fd6c0; }}
  }}
  h1 {{ font-size: 30px; line-height: 1.2; margin: 0 0 4px; }}
  h2 {{ font-size: 19px; margin: 32px 0 8px; }}
  .updated {{ font-size: 13px; opacity: .6; margin: 0 0 28px; }}
  .intro {{ font-size: 18px; }}
  p {{ margin: 0 0 12px; }}
  footer {{ margin-top: 48px; font-size: 14px; opacity: .6; }}
  a {{ color: #1f5a51; }}
</style>
</head>
<body>
<h1>{title}</h1>
<p class="updated">обновлено {updated}</p>
{body}
<footer><p>Того — дневник собаки. <a href="index.html">О приложении</a></p></footer>
</body>
</html>
"""

INDEX = """<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Того — дневник собаки</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{
    margin: 0 auto; padding: 48px 20px; max-width: 34rem;
    font: 17px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    color: #1c1c1e; background: #fff;
  }}
  @media (prefers-color-scheme: dark) {{
    body {{ color: #f2f2f7; background: #111; }}
    a {{ color: #6fd6c0; }}
  }}
  h1 {{ font-size: 34px; margin: 0 0 8px; }}
  p {{ margin: 0 0 16px; }}
  ul {{ padding-left: 20px; }}
  a {{ color: #1f5a51; }}
</style>
</head>
<body>
<h1>Того</h1>
<p>Дневник собаки: когда выводили, когда кормили, каким был стул.
Два тапа — и вечером никто ничего не выясняет.</p>
<p>Всё считается на телефоне. Аккаунт не нужен.</p>
<h2>Поддержка</h2>
<p>Пишите на <a href="mailto:{support}">{support}</a> — отвечает человек,
обычно в течение двух рабочих дней. Если что-то в приложении мешает
ухаживать за собакой, пишите сразу: это важнее новых возможностей.</p>
<h2>Документы</h2>
<ul>
  <li><a href="privacy.html">Политика конфиденциальности</a></li>
  <li><a href="terms.html">Условия использования</a></li>
</ul>
</body>
</html>
"""


def render(doc):
    parts = []
    if doc["intro"]:
        parts.append('<p class="intro">%s</p>' % html.escape(doc["intro"]))
    for title, paragraphs in doc["sections"]:
        parts.append("<h2>%s</h2>" % html.escape(title))
        for paragraph in paragraphs:
            text = html.escape(paragraph)
            # Адрес почты делаем ссылкой: на странице поддержки её нажимают.
            for address in (PRIVACY, SUPPORT):
                text = text.replace(address, f'<a href="mailto:{address}">{address}</a>')
            parts.append("<p>%s</p>" % text)
    return PAGE.format(title=html.escape(doc["title"]),
                       updated=html.escape(doc["updated"]),
                       body="\n".join(parts))


os.makedirs(OUT, exist_ok=True)

for screen, name in (("PrivacyPolicyScreen", "privacy.html"),
                     ("TermsScreen", "terms.html")):
    doc = extract(screen)
    open(os.path.join(OUT, name), "w", encoding="utf-8").write(render(doc))
    print(f"→ site/{name}  ({len(doc['sections'])} разделов)")

open(os.path.join(OUT, "index.html"), "w", encoding="utf-8").write(
    INDEX.format(support=SUPPORT))
print("→ site/index.html")
