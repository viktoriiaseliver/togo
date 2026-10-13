#!/usr/bin/env python3
"""iOS code syntax для переменных Figma: `figma-имя → Token.Группа.имя`.

Пишет `DesignTokens/ядро-дизайна/figma-plugin/пары-ios.json` и проверяет
КАЖДОЕ имя по `TogoShared/Generated/Tokens.generated.swift`.

    python3 Tools/пары_ios.py           # собрать и проверить
    python3 Tools/пары_ios.py --проверить  # только проверить, не писать

## Зачем

Dev Mode показывает дизайнеру ровно одну строку про наш код — code
syntax переменной. Сегодня `iosName()` в плагине печатает
`Color("fill.1")`: это форма имени АССЕТ-КАТАЛОГА, которой у Togo нет
вовсе — цвет живёт `Color(Dyn(dark:light:darkHC:lightHC:))`. Замер
13.10.2026: функция печатает 135 имён, из них существует в Swift
**ноль**. Даже «почти верные» неверны — `Space.s12` против
`Token.Space.s12`, и bare-формы в коде нет ни одной.

> Ярлык, который печатает сам инструмент, не является его замером:
> он печатается до работы и от её исхода не зависит.

## Три правила, на которых стоит сборка

**1. Пара, которую никто не объявил, не печатается.** Пустой code
syntax честен, выдуманный — нет, и проверить его дизайнеру нечем.
Пары берутся тем же разбором, что в `сверка_токенов_с_фигмой.py`
(импортом, не копией): описание токена называет имя Figma прозой
или CSS-переменную.

**2. Матч по значению основанием пары не является.** Прогон показал,
почему: `size/toggle-h` и `size/clear` оба равны 36 и оба «совпали» бы
с `Token.Size.handleW` — ручка шторки оказалась бы тумблером.

**3. Имя берётся у СЕМАНТИКИ, а не у примитива.** Примитивы в Swift
лежат в `fileprivate enum Общие` и снаружи недоступны: напечатать
`Общие.night1` значило бы дать дизайнеру имя, которого он в коде
не найдёт. Поэтому для переменной Figma ищется семантический или
компонентный токен, который на неё ссылается, — и печатается его имя.

Если на одну переменную Figma ссылаются несколько семантических
токенов с разными именами — code syntax не печатается, и такая
переменная называется в отчёте. Выбирать за человека, какая из ролей
«главная», инструмент не вправе.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS = ROOT / "Tools"
SWIFT = ROOT / "TogoShared/Generated/Tokens.generated.swift"
ВЫХОД = ROOT / "DesignTokens/ядро-дизайна/figma-plugin/пары-ios.json"
CODE_JS = ROOT / "DesignTokens/ядро-дизайна/figma-plugin/code.js"

# Порог «было что сверять». Меньше — разбор ослеп, и пустой словарь
# выглядел бы как «пар нет по природе вещей».
MIN_ПАР = 15


def загрузить(имя: str, путь: pathlib.Path):
    """Импорт модуля по пути: имена файлов кириллицей обычным
    `import` не берутся."""
    спец = importlib.util.spec_from_file_location(имя, путь)
    модуль = importlib.util.module_from_spec(спец)
    спец.loader.exec_module(модуль)
    return модуль


сверка = загрузить("сверка", TOOLS / "сверка_токенов_с_фигмой.py")
генератор = загрузить("генератор", TOOLS / "generate_tokens.py")


def swift_имена() -> set[str]:
    """Полные имена вида `Token.Surface.card` из сгенерированного файла.

    Читается ФАЙЛ, а не наша таблица групп: приёмка берётся у того,
    что зависит от работы генератора, а не у того, что мы про него
    думаем.
    """
    текст = SWIFT.read_text(encoding="utf-8")
    имена: set[str] = set()
    стек: list[str] = []
    for строка in текст.splitlines():
        t = строка.strip()
        if t.startswith("//") or t.startswith("///"):
            continue
        # Модификаторы перечислять нельзя — надо брать любые.
        # Первая редакция знала `fileprivate|public|private` и не знала
        # `nonisolated`, которым объявлен САМ контейнер `Token`.
        # Разбор тихо собрал 44 имени без головы (`Surface.card` вместо
        # `Token.Surface.card`), не нашёл ни одного из них в файле
        # и доложил «code syntax собран 0». Порог «я ослеп» это поймал;
        # без него словарь вышел бы пустым и выглядел бы как ответ.
        m = re.match(r"(?:\w+\s+)*enum (\w+)", t)
        if m:
            стек.append(m.group(1))
            continue
        if t == "}" and стек:
            стек.pop()
            continue
        m = re.match(r"static (?:let|var) (\w+)", t)
        if m and стек:
            имена.add(".".join(стек + [m.group(1)]))
    return имена


def swift_имя_токена(путь: str) -> str | None:
    """`semantic.surface.card` → `Token.Surface.card`.

    Соответствие «путь токена → группа Swift» берётся из таблицы
    самого генератора (`GROUPS`), а не пишется здесь заново: две
    таблицы одного соответствия разошлись бы молча.
    """
    for префикс, группа, *_ in генератор.GROUPS:
        if путь.startswith(префикс + "."):
            хвост = путь[len(префикс) + 1:]
            части = [генератор.swift_name(ч) for ч in хвост.split(".")]
            # Внутри `Component` вложенность сохраняется с заглавной:
            # `component.button.primary.background`
            # → `Token.Component.Button.Primary.background`.
            if len(части) > 1:
                части = [генератор.camel(ч)[:1].upper() + генератор.camel(ч)[1:]
                         for ч in хвост.split(".")[:-1]] + [части[-1]]
            return ".".join(["Token", группа] + части)
    if путь.startswith("component."):
        части = путь.split(".")[1:]
        головы = [генератор.camel(ч)[:1].upper() + генератор.camel(ч)[1:] for ч in части[:-1]]
        return ".".join(["Token", "Component"] + головы + [генератор.swift_name(части[-1])])
    return None


def вшить_в_плагин(словарь: dict[str, str]) -> None:
    """Строка `const PAIRS_IOS = {…};` в `code.js`, рядом с `DATA`.

    **Почему вшиваем, а не читаем файл.** Плагин Figma живёт в песочнице
    и файлов с диска не читает вовсе. Оставь словарь только в JSON —
    и получится механизм без входа: файл есть, читателя нет, и отличить
    это от рабочего нельзя ни грепом, ни запуском. У нас такой уже
    лежит рядом — пять связок Code Connect с `REPLACE_WITH_FILE_KEY`.

    JSON при этом остаётся: он читаемый в диффе и его смотрит человек.
    Расхождение двух копий ловится тем, что обе пишет один проход.
    """
    текст = CODE_JS.read_text(encoding="utf-8")
    строка = "const PAIRS_IOS = " + json.dumps(словарь, ensure_ascii=False, sort_keys=True) + ";"
    if "const PAIRS_IOS = " in текст:
        новый = re.sub(r"^const PAIRS_IOS = .*;$", строка.replace("\\", "\\\\"),
                       текст, count=1, flags=re.M)
    else:
        # Сразу после `DATA`: порядок объявления важен только человеку,
        # читающему файл, — обе константы берутся из одного источника.
        конец = текст.index("\n", текст.index("const DATA")) + 1
        новый = текст[:конец] + строка + "\n" + текст[конец:]
    CODE_JS.write_text(новый, encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--проверить", action="store_true",
                    help="только проверить, файл не писать")
    args = ap.parse_args()

    репо = сверка.leaves(json.loads(
        (ROOT / "DesignTokens/tokens.json").read_text(encoding="utf-8")))
    данные = сверка.данные_плагина(
        (ROOT / "DesignTokens/ядро-дизайна/figma-plugin/code.js").read_text(encoding="utf-8"))
    фигма = сверка.figma_variables(данные)

    пары, _, _ = сверка.найти_пары(репо, фигма)
    по_пути = {p: (v, d) for p, v, d in репо}
    пара_примитива = {путь: v for путь, v, _ in пары}

    # Переменная Figma → список (наш путь, Swift-имя).
    кандидаты: dict[str, list[tuple[str, str]]] = {}
    for путь, _, _ in репо:
        if not путь.startswith(("semantic.", "component.")):
            continue
        цепочка = сверка.resolve_chain(путь, по_пути)
        переменная = пара_примитива.get(цепочка[-1])
        if переменная is None:
            continue
        имя = swift_имя_токена(путь)
        if имя is None:
            continue
        кандидаты.setdefault(переменная["name"], []).append((путь, имя))

    живые = swift_имена()
    словарь: dict[str, str] = {}
    неоднозначные: dict[str, list[str]] = {}
    нет_в_swift: list[str] = []

    for фигма_имя, список in sorted(кандидаты.items()):
        имена = sorted({имя for _, имя in список})
        # **Среди нескольких ролей предпочитается СЕМАНТИЧЕСКАЯ.**
        # Это правило, а не выбор за человека: компонентные токены
        # ссылаются на семантические, то есть семантика — общий адрес
        # той же величины, а компонент — частный случай. Дизайнер,
        # выбирая переменную в пикере, выбирает роль, а не компонент:
        # `color/fill/1` он ставит и на карточку, и на чип, и назвать
        # ему `Component.Chip.restBackground` значило бы соврать
        # в девяти случаях из десяти.
        #
        # Если семантических несколько — не печатаем. У `color/fill/1`
        # их две (`Action.secondary` и `Surface.control`), и какая
        # «главная», знает человек, а не инструмент.
        семантические = [и for и in имена if not и.startswith("Token.Component.")]
        if len(семантические) == 1:
            имена = семантические
        if len(имена) > 1:
            неоднозначные[фигма_имя] = имена
            continue
        имя = имена[0]
        if имя not in живые:
            нет_в_swift.append(f"{фигма_имя} → {имя}")
            continue
        словарь[фигма_имя] = имя

    print(f"переменных в плагине      {len(фигма)}")
    print(f"пар по объявлению         {len(пары)}")
    print(f"code syntax собран        {len(словарь)}")
    print(f"неоднозначных             {len(неоднозначные)}")
    print(f"нет в Tokens.generated    {len(нет_в_swift)}")
    print()

    if len(словарь) < MIN_ПАР:
        print("Я ОСЛЕП — пар меньше ожидаемого, словарь не пишу:")
        print(f"  собрано {len(словарь)}, ждал ≥{MIN_ПАР}")
        print("  Пустой словарь выглядит как «пар нет по природе вещей».")
        return 2

    if нет_в_swift:
        print("ИМЯ НАЗВАНО, НО В СГЕНЕРИРОВАННОМ ФАЙЛЕ ЕГО НЕТ:")
        for s in нет_в_swift:
            print(f"  {s}")
        print("  Это и есть приёмка: она берётся у того, что зависит")
        print("  от работы генератора, а не у нашей таблицы групп.")
        print()

    if неоднозначные:
        print("НЕОДНОЗНАЧНЫЕ — code syntax НЕ печатается:")
        for фигма_имя, имена in sorted(неоднозначные.items()):
            print(f"  {фигма_имя:<30} {', '.join(имена)}")
        print("  Выбирать за человека, какая роль главная, инструмент не вправе.")
        print()

    if not args.проверить:
        ВЫХОД.write_text(
            json.dumps(словарь, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8")
        print(f"записано: {ВЫХОД.relative_to(ROOT)}")
        вшить_в_плагин(словарь)
        print(f"вшито в:  {CODE_JS.relative_to(ROOT)}")

    print()
    print("ЧЕГО ЭТОТ СБОРЩИК НЕ ДЕЛАЕТ:")
    print("  · не выдумывает пару по совпадению значения: `size/toggle-h`")
    print("    и `size/clear` оба 36, и пара по числу — это пара по совпадению")
    print("  · не печатает имя примитива: в Swift они `fileprivate enum Общие`,")
    print("    и дизайнер такого имени в коде не найдёт")
    print("  · не проверяет, что сам плагин ПРОЧИТАЛ этот файл: это видно")
    print("    только в Dev Mode после запуска плагина")
    return 1 if нет_в_swift else 0


if __name__ == "__main__":
    sys.exit(main())
