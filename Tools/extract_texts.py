#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Того · сбор всех текстов интерфейса.

Зачем: живому переводчику нужен один документ, а не двадцать файлов кода.
Скрипт вынимает из исходников все строки с кириллицей — то есть ровно то,
что видит человек, — и складывает в два вида:

  docs/TEXTS.md                     таблица для переводчика: где, что, контекст
  Togo/Resources/Localizable.xcstrings   каталог строк для Xcode

Каталог строк лежит в git обычным JSON: перевод приезжает пул-реквестом
и виден в диффе построчно. Для переводчика, который не работает с git,
есть XLIFF: `make loc-export` кладёт .xcloc, который открывается любым
переводческим редактором, а `make loc-import` вливает его обратно.

    python3 Tools/extract_texts.py
"""

import hashlib
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = ["Togo", "TogoShared", "TogoWidgets"]
SKIP_DIRS = {"Generated"}
SKIP_FILES = {"ComponentGallery.swift"}

MD_OUT = os.path.join(ROOT, "docs", "TEXTS.md")
CATALOG_OUT = os.path.join(ROOT, "Togo", "Resources", "Localizable.xcstrings")

CYRILLIC = re.compile(r"[А-Яа-яЁё]")
LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
# Подстановки в переводе становятся плейсхолдерами: переводчик двигает их
# по фразе, но не переписывает.
INTERPOLATION = re.compile(r"\\\(([^()]*(?:\([^()]*\))?[^()]*)\)")
# Технические строки: в логи и в служебные ключи переводчику лезть незачем.
TECHNICAL = re.compile(r"\blog\.(error|notice|debug|info|warning)\b")
DECL = re.compile(r"^\s*(?:@\w+\s+)*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?"
                  r"(struct|enum|final class|class|extension|func|var|let|case)\s+([A-Za-z_][A-Za-z0-9_]*)")
MARK = re.compile(r"^\s*//\s*MARK:\s*-?\s*(.+)$")

# Как называется экран для переводчика — по имени файла.
SCREEN_TITLES = {
    "OnboardingFlow.swift": "Онбординг",
    "TodayScreen.swift": "Главный экран · Сегодня",
    "DayTimeline.swift": "Лента дня и режим дня",
    "ActionGrid.swift": "Кнопки действий",
    "TodayRouter.swift": "Шторка «Ещё»",
    "NeedsSheet.swift": "Просится · вердикт",
    "WalkSheets.swift": "Выход и прогулка",
    "LogSheets.swift": "Записи · стул, еда, вода, лакомство, заметка",
    "IncidentSheet.swift": "Инцидент",
    "TrainingSessionScreen.swift": "Занятие · точность маркера",
    "TrainingScreens.swift": "Итог занятия, перенос навыка, процедуры",
    "HistoryScreen.swift": "История",
    "HealthScreen.swift": "Здоровье",
    "FamilyScreen.swift": "Семья",
    "ProfileScreen.swift": "Профиль и уход",
    "Editors.swift": "Формы: собака, напоминание, препарат",
    "FeedingScreen.swift": "Питание и режим",
    "TripScreens.swift": "Поездка",
    "SettingsScreen.swift": "Настройки",
    "LegalScreens.swift": "Правовые тексты",
    "DataPrivacyScreen.swift": "Данные, поддержка, о приложении",
    "HowItWorksScreen.swift": "Как это работает",
    "PaywallScreen.swift": "Подписка",
    "DowngradeScreen.swift": "Отключение подписки",
    "Enums.swift": "Словарь: виды записей, роли, формы стула",
    "NeedVerdict.swift": "Формулировки вердикта",
    "Formatting.swift": "Числа и окончания",
    "Feeding.swift": "Питание · формулировки отчёта",
    "Subscriptions.swift": "Подписка · список возможностей",
    "Notifications.swift": "Уведомления",
    "SeedData.swift": "Стартовые напоминания",
    "TodayWidget.swift": "Виджет",
    "WalkLiveActivity.swift": "Live Activity",
}


def swift_files():
    for source in SOURCES:
        for base, dirs, files in os.walk(os.path.join(ROOT, source)):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for name in sorted(files):
                if name.endswith(".swift") and name not in SKIP_FILES:
                    yield os.path.join(base, name)


def key_id(text):
    """Короткий устойчивый идентификатор строки.

    Ключом в каталоге служит сам русский текст — так устроены строковые
    каталоги Xcode. Но ссылаться в переписке на длинную фразу неудобно,
    поэтому у каждой строки есть ещё и короткий id: он не меняется, пока
    не меняется текст, и одинаков в документе и в правках.
    """
    return "T-" + hashlib.sha1(text.encode("utf-8")).hexdigest()[:6].upper()


def placeholders(text):
    """\(dog.name) → %@. Что именно подставляется, видно в колонке «Где»."""
    return INTERPOLATION.sub("%@", text)


def strip_comments(line):
    """Грубо, но достаточно: строк с // внутри кавычек у нас нет."""
    index = line.find("//")
    if index == -1:
        return line
    quotes = line[:index].count('"') - line[:index].count('\\"')
    return line if quotes % 2 else line[:index]


def collect():
    """Возвращает [(файл, [(строка, контекст, номер)])]."""
    result = []
    for path in swift_files():
        rel = os.path.relpath(path, ROOT)
        context = ""
        found = []
        for number, raw in enumerate(open(path, encoding="utf-8"), 1):
            mark = MARK.match(raw)
            if mark:
                context = mark.group(1).strip()
                continue
            decl = DECL.match(raw)
            if decl:
                context = decl.group(2)
            line = strip_comments(raw)
            if TECHNICAL.search(line):
                continue
            for literal in LITERAL.findall(line):
                if not CYRILLIC.search(literal):
                    continue
                found.append((placeholders(literal), context, number))
        if found:
            result.append((rel, found))
    return result


def markdown(collected):
    total = sum(len(items) for _, items in collected)
    unique = {text for _, items in collected for text, _, _ in items}

    lines = [
        "# Тексты интерфейса",
        "",
        "Полный список ключей локализации со всеми строками, которые видит",
        "человек. Один файл — всё, что нужно переводчику.",
        "",
        "Собрано скриптом `Tools/extract_texts.py` из исходников. Файл",
        "перегенерируется командой `make texts` — править его руками не нужно:",
        "правки потеряются. Менять текст надо в коде, а перевод — в",
        "`Togo/Resources/Localizable.xcstrings`.",
        "",
        f"Строк всего: **{total}**, различных ключей: **{unique.__len__()}**.",
        "",
        "## Как читать таблицы",
        "",
        "* **ID** — короткий устойчивый идентификатор строки. Ссылайтесь на него",
        "  в вопросах и правках; он не меняется, пока не меняется русский текст.",
        "* **Русский · он же ключ** — то же значение, что стоит ключом в",
        "  `Togo/Resources/Localizable.xcstrings`. Так устроены строковые каталоги",
        "  Xcode: ключ — это исходная фраза, отдельных `screen.button.title` нет.",
        "* **Где** — имя функции или свойства в коде и номер строки: по нему видно,",
        "  в каком месте экрана фраза появляется.",
        "* **EN / FR** — колонки под перевод.",
        "",
        "## Что нужно от переводчика",
        "",
        "1. Перевести колонку «Русский» на английский и французский.",
        "2. Сохранить тон: короткие предложения, обращение на «ты» к владельцу,",
        "   никакого маркетингового восторга. Приложение говорит спокойно и по делу.",
        "3. Не переводить дословно там, где по-русски идиома. Например",
        "   «Закончить на удаче» — это про то, чтобы завершить занятие на",
        "   получившемся повторе, а не про везение.",
        "4. Термины держать одинаковыми во всём приложении: «выход» (не «прогулка»),",
        "   «занятие» (не «дрессировка»), «маркер» (не «команда»), «эпизод».",
        "5. Слова «событие», «лог», «синхронизация», «валидация» в интерфейсе",
        "   не употребляются намеренно — в переводе тоже не должны появиться.",
        "6. `%@` — подстановка: туда приложение вставит кличку, число или время.",
        "   Плейсхолдер можно двигать по фразе, но нельзя убирать и нельзя",
        "   менять местами, если их несколько.",
        "",
        "## Чувствительные места",
        "",
        "Эти формулировки выбирались вместе с кинологом, менять их смысл нельзя:",
        "",
        "* **«Не наказывай»** после лужи — приложение обязано сказать это прямо,",
        "  один раз, без морали.",
        "* **«Не брал еду»** в занятии — это про то, что задача была слишком",
        "  сложной, а не про упрямство собаки.",
        "* **«Непонятно»** в вердикте — честное признание, что данных мало.",
        "  Не заменять на «нет данных» или «ошибка».",
        "* **Оценка занятия описывает условия, а не собаку.** Никаких «плохо»,",
        "  «хуже», «не слушается».",
        "* **Дисклеймер** про то, что приложение не медицинское устройство,",
        "  переводится буквально: это юридический текст.",
        "",
        "---",
        "",
    ]

    for path, items in collected:
        name = os.path.basename(path)
        title = SCREEN_TITLES.get(name, name)
        lines += [f"## {title}", "", f"`{path}`", "",
                  "| ID | Русский · он же ключ | Где | EN | FR |",
                  "|---|---|---|---|---|"]
        seen = set()
        for text, context, number in items:
            if text in seen:
                continue
            seen.add(text)
            cell = text.replace("|", "\\|").replace("\n", " ")
            lines.append(f"| `{key_id(text)}` | {cell} | {context or '—'}:{number} |  |  |")
        lines.append("")

    return "\n".join(lines) + "\n"


# Языки, которые попадают в сборку.
#
# Пока только русский. Пустые английский и французский здесь были —
# и Xcode честно собирал из них `en.lproj` и `fr.lproj`. App Store берёт
# список языков из этих папок, а не из Info.plist: карточка приложения
# обещала бы английский и французский, а интерфейс оставался русским.
#
# Документ для переводчика от этого не страдает: ключи целиком лежат
# в `docs/TEXTS.md`, и он не зависит от того, что собрано в бандл.
# Когда перевод вернётся — дописать сюда язык и заполнить значения.
BUNDLED_LANGUAGES = ("ru",)


def catalog(collected):
    """String Catalog: русский — источник."""
    strings = {}
    for _path, items in collected:
        for text, context, _number in items:
            entry = strings.setdefault(text, {"extractionState": "manual", "localizations": {}})
            if context and "comment" not in entry:
                entry["comment"] = context
            entry["localizations"]["ru"] = {
                "stringUnit": {"state": "translated", "value": text}
            }
            for language in BUNDLED_LANGUAGES:
                if language == "ru":
                    continue
                entry["localizations"].setdefault(language, {
                    "stringUnit": {"state": "new", "value": ""}
                })
    return json.dumps(
        {"sourceLanguage": "ru", "strings": dict(sorted(strings.items())), "version": "1.0"},
        ensure_ascii=False,
        indent=2,
    ) + "\n"


def main():
    collected = collect()
    if not collected:
        sys.exit("Ничего не нашлось — проверь пути в SOURCES")

    os.makedirs(os.path.dirname(MD_OUT), exist_ok=True)
    os.makedirs(os.path.dirname(CATALOG_OUT), exist_ok=True)
    open(MD_OUT, "w", encoding="utf-8").write(markdown(collected))
    open(CATALOG_OUT, "w", encoding="utf-8").write(catalog(collected))

    total = sum(len(items) for _, items in collected)
    print("→ %s" % os.path.relpath(MD_OUT, ROOT))
    print("→ %s" % os.path.relpath(CATALOG_OUT, ROOT))
    unique = {text for _path, items in collected for text, _c, _n in items}
    print("%d строк, %d ключей, %d файлов" % (total, len(unique), len(collected)))


if __name__ == "__main__":
    main()
