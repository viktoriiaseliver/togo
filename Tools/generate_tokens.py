#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Того · генератор токенов.

Один вход — DesignTokens/tokens.json (формат W3C Design Tokens).
Три выхода:
  • Togo/DesignSystem/Generated/Tokens.generated.swift  — для приложения
  • DesignTokens/build/tokens.css                       — для макета в вебе
  • DesignTokens/build/figma-variables.json             — для импорта в Figma

Правило одностороннее: руками правится только tokens.json.
Сгенерированные файлы не редактируются никогда — их перезапишет `make tokens`.
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "DesignTokens", "tokens.json")
SWIFT_OUT = os.path.join(ROOT, "TogoShared", "Generated", "Tokens.generated.swift")
CSS_OUT = os.path.join(ROOT, "DesignTokens", "build", "tokens.css")
FIGMA_OUT = os.path.join(ROOT, "DesignTokens", "build", "figma-variables.json")

ALIAS = re.compile(r"^\{([^}]+)\}$")

# Четыре режима системы: тема × повышенный контраст. Ровно те четыре,
# которые несёт коллекция `Theme` пакета Graphite и которые умеет
# выбирать сама iOS, — больше в `UITraitCollection` ничего про цвет нет.
#
# Светлой темы у нас не было СТРУКТУРНО до 07.10.2026: из 174 листьев
# словарь вместо значения стоял у двух, и оба — тени. Единственное
# вхождение слова `light` жило в `emit_figma` ярлыком на выгрузке,
# под которым в Фигму уезжала ТЁМНАЯ палитра.
MODES = ("dark", "light", "darkHC", "lightHC")


def is_modal(value):
    """Значение задано по режимам, а не одним цветом.

    Проверяется полным набором ключей, а не наличием одного: у тени
    `$value` тоже словарь (`color`, `offsetX`, `blur`…), и проверка
    «это словарь» спутала бы их. Сравнение префиксом или одним ключом
    здесь дало бы ровно ту ошибку, за которую мы платили на `Swatch`
    против `SwatchRow`.
    """
    return isinstance(value, dict) and set(value) == set(MODES)


# ---------------------------------------------------------------- разбор

def load():
    with open(SRC, encoding="utf-8") as f:
        return json.load(f)


def is_token(node):
    return isinstance(node, dict) and "$value" in node


def walk(node, path, inherited_type=None, out=None):
    """Собирает плоскую карту путь -> (тип, значение, описание)."""
    out = {} if out is None else out
    node_type = node.get("$type", inherited_type) if isinstance(node, dict) else inherited_type
    if is_token(node):
        out[".".join(path)] = (node.get("$type", inherited_type), node["$value"], node.get("$description"))
        return out
    for key, child in node.items():
        if key.startswith("$"):
            continue
        walk(child, path + [key], node_type, out)
    return out


def resolve(flat, value, seen=None):
    """Разворачивает ссылки вида {primitive.color.ochre} до конечного значения."""
    seen = seen or set()
    if isinstance(value, str):
        m = ALIAS.match(value.strip())
        if m:
            target = m.group(1)
            if target in seen:
                sys.exit("Циклическая ссылка в токенах: %s" % target)
            if target not in flat:
                sys.exit("Ссылка на несуществующий токен: %s" % target)
            return resolve(flat, flat[target][1], seen | {target})
    if isinstance(value, dict):
        return {k: resolve(flat, v, seen) for k, v in value.items()}
    return value


# ------------------------------------------------------------ помощники

def hex_literal(value):
    """Восьмизначный хекс больше не обрезаем.

    Раньше альфа молча отбрасывалась: `#FFFFFF12` превращался в белый.
    В светлой теме это было незаметно, в тёмной — половина токенов
    задана долей белого, и обрезка сделала бы их все сплошными."""
    return "0x" + value.lstrip("#").upper()


def modal_key(resolved):
    return tuple(hex_literal(resolved[m]) for m in MODES)


def shared_palette(flat):
    """Имя общего цвета на каждое РАЗНОЕ значение по режимам.

    **Зачем вообще, и это не экономия строк.** `Color(Dyn(…))` делает
    `UIColor(dynamicProvider:)`, а два таких объекта с одинаковыми
    значениями **не равны**: равенство у динамического цвета по
    объекту, не по значению. Первая редакция печатала `Color(Dyn(…))`
    на каждый токен, и три утверждения в `DesignTokenTests` упали —
    те, что говорят «эти две роли это один токен»:

        Component.Button.Primary.background == Action.primary
        Component.Timeline.nowMarker        == Action.primary
        Component.Button.Primary.label      == Ink.onAccent

    Значения у них совпадали до байта. Сторожа были правы, сломал их я.

    > **Переход на динамический цвет отнимает у токенов равенство по
    > значению.** Сторож, выражающий правило через `==` двух токенов,
    > краснеет не на правиле, а на устройстве цвета — и выглядит это
    > как регрессия палитры.

    Поэтому одно значение — один объект: токены с совпадающими
    режимами смотрят на одну константу, и `==` снова означает
    «один токен».

    Имя берётся у ПЕРВОГО по алфавиту токена с этим значением —
    детерминированно, чтобы диф сгенерированного файла не плясал
    от порядка обхода.
    """
    # Порядок предпочтения, а не алфавит. Первая редакция брала просто
    # первый по алфавиту — и `component.*` всегда опережал `primitive.*`,
    # отчего `Ink.primary` получал имя `Общие.finishLabel`: цвет чернил,
    # названный подписью кнопки «закончить».
    #
    # **Имя общего цвета читают там, где его употребляют, а не там,
    # откуда оно взялось.** Поэтому имя берётся у ПРИМИТИВА — он и есть
    # то, чем значение является; семантика и компонент только ссылаются.
    СЛОЙ = {"primitive": 0, "semantic": 1, "component": 2}
    первые = {}
    for key in sorted(flat, key=lambda k: (СЛОЙ.get(k.split(".")[0], 9), k.count("."), k)):
        token_type, value, _note = flat[key]
        if token_type != "color":
            continue
        resolved = resolve(flat, value)
        if not is_modal(resolved):
            continue
        первые.setdefault(modal_key(resolved), key)
    палитра = {}
    for ключ, путь in первые.items():
        части = [ч for ч in путь.split(".") if ч not in ("primitive", "color")]
        палитра[ключ] = camel("-".join(части[-2:]))
    return палитра


def swift_color(resolved, палитра):
    """Одно место, где цвет превращается в Swift.

    Их было два — `emit_swift` и `emit_component_tree`, — и первая
    редакция режимов научила только первое. Падение пришло из второго,
    и это наш записанный класс: **третья реализация одного правила
    молчала в двух случаях из трёх**. Теперь реализация одна, и её
    зовут оба.
    """
    if is_modal(resolved):
        return "Общие.%s" % палитра[modal_key(resolved)]
    return "Color(hex: %s)" % hex_literal(resolved)


def px(value):
    return float(str(value).replace("px", "").replace("ms", ""))


def camel(name):
    parts = re.split(r"[-_ ]+", name)
    head = parts[0]
    return head + "".join(p[:1].upper() + p[1:] for p in parts[1:])


def pascal(name):
    c = camel(name)
    return c[:1].upper() + c[1:]


def swift_name(key):
    """Числовые ключи (space.12) в Swift становятся s12."""
    return ("s" + key) if key[:1].isdigit() else camel(key)


def doc(text, indent):
    if not text:
        return []
    return ["%s/// %s" % (indent, line) for line in text.split("\n")]


# --------------------------------------------------------------- Swift

# Какая группа токенов во что превращается в Swift.
GROUPS = [
    ("semantic.surface", "Surface", "color", "Поверхности: бумага, карточка, утопленное, хайрлайн."),
    ("semantic.text", "Ink", "color", "Текст. `faint` — 2,5:1, текстом и значками НЕ красится ни в каком кегле: разрешение «только с 14pt» было неверным и развело его по двадцати четырём файлам."),
    ("semantic.action", "Action", "color", "Действия. Охряная кнопка строго одна на экран."),
    ("semantic.status", "Status", "color", "Состояния: янтарь — «подожди», терракот — просрочка или кровь."),
    ("semantic.spacing", "Spacing", "dimension", "Отступы."),
    ("semantic.radius", "Radius", "dimension", "Радиусы."),
    ("semantic.poster", "Poster", "color", "Плакат — верхняя треть «Сегодня» и «На улице». Цвет блока = РЕЖИМ ДНЯ, и правило выбора в `TogoShared/Domain/PosterMode.swift`, не во вью: его спрашивают экран, виджет и «остров». Шторки плаката не несут."),
    ("primitive.space", "Space", "dimension", "Шаг сетки. Прикладной код берёт Spacing, а не это."),
    ("primitive.size", "Size", "dimension", "Размеры контролов и иконок."),
    ("primitive.font.size", "FontSize", "dimension", "Кегли."),
    ("primitive.font.weight", "FontWeight", "fontWeight", "Начертания."),
    ("primitive.duration", "Duration", "duration", "Длительности анимаций."),
]

# Карта полная по шкале SwiftUI, а не по тем весам, что сегодня в токенах.
# 05.10: токены получили 300 под крупные цифры поколения «финал», карта
# знала только 400–900, и сторож ниже честно назвал себя и сказал, что
# чинить. Он сработал как задуман; дырой было то, что карта описывала
# НАШЕ ТЕКУЩЕЕ УПОТРЕБЛЕНИЕ, а не шкалу, из которой выбирают: половина
# шкалы отсутствовала, и любой вес легче regular упал бы так же.
WEIGHT_MAP = {100: ".ultraLight", 200: ".thin", 300: ".light",
              400: ".regular", 500: ".medium", 600: ".semibold", 700: ".bold",
              800: ".heavy", 900: ".black"}


def swift_weight(value):
    """Вес CSS → Font.Weight.

    Неизвестный вес называет себя и говорит, что с ним делать. Прежде
    здесь стоял прямой доступ к словарю: 800 из «Льда» дал `KeyError: 800`
    посреди трассировки, и по ней не видно ни файла-источника, ни того,
    что чинить — карту или токен.
    """
    n = int(value)
    if n not in WEIGHT_MAP:
        raise SystemExit(
            "tokens.json: вес %s не имеет пары в SwiftUI. Известны: %s.\n"
            "Добавь пару в WEIGHT_MAP или поправь вес в токенах."
            % (n, ", ".join(str(k) for k in sorted(WEIGHT_MAP)))
        )
    return WEIGHT_MAP[n]


def emit_swift(raw, flat):
    lines = [
        "// Сгенерировано Tools/generate_tokens.py из DesignTokens/tokens.json.",
        "// Не редактировать руками: правки перезапишет `make tokens`.",
        "//",
        "// Источник правды — tokens.json. Тот же файл импортируется в Figma",
        "// как коллекции переменных, поэтому имена здесь и имена в Figma совпадают.",
        "",
        "import SwiftUI",
        "",
        "/// Токены Того. Экраны читают Semantic и Component; Primitive — только",
        "/// внутри дизайн-системы.",
        "nonisolated enum Token {",
    ]

    палитра = shared_palette(flat)
    if палитра:
        lines.append("")
        lines += doc(
            "Общие динамические цвета: ОДИН объект на одно значение.\n"
            "\n"
            "`Color(Dyn(…))` делает `UIColor(dynamicProvider:)`, а два таких\n"
            "объекта с одинаковыми значениями НЕ РАВНЫ — равенство у\n"
            "динамического цвета по объекту, не по значению. Пока каждый\n"
            "токен получал свой `Dyn`, три утверждения `DesignTokenTests`\n"
            "падали на верных значениях: `Button.Primary.background ==\n"
            "Action.primary`, `Timeline.nowMarker == Action.primary`,\n"
            "`Button.Primary.label == Ink.onAccent`.\n"
            "\n"
            "Переход на динамический цвет отнимает у токенов равенство\n"
            "по значению; сторож, выражающий правило через `==` двух\n"
            "токенов, краснеет не на правиле, а на устройстве цвета.\n"
            "Одно значение — один объект, и `==` снова означает «один токен».",
            "    ")
        lines.append("    fileprivate enum Общие {")
        обратно = {}
        for ключ, имя in палитра.items():
            обратно[имя] = ключ
        for имя in sorted(обратно):
            d, l, dhc, lhc = обратно[имя]
            lines.append("        static let %s = Color(Dyn(dark: %s, light: %s, darkHC: %s, lightHC: %s))"
                         % (имя, d, l, dhc, lhc))
        lines.append("    }")

    for prefix, enum_name, kind, description in GROUPS:
        entries = [(k, v) for k, v in flat.items() if k.startswith(prefix + ".")]
        if not entries:
            continue
        lines.append("")
        lines += doc(description, "    ")
        lines.append("    enum %s {" % enum_name)
        for key, (_type, value, note) in sorted(entries):
            leaf = key[len(prefix) + 1:]
            resolved = resolve(flat, value)
            lines += doc(note, "        ")
            if kind == "color":
                lines.append("        static let %s = %s" % (swift_name(leaf), swift_color(resolved, палитра)))
            elif kind == "dimension":
                lines.append("        static let %s: CGFloat = %g" % (swift_name(leaf), px(resolved)))
            elif kind == "duration":
                lines.append("        static let %s: Double = %g" % (swift_name(leaf), px(resolved) / 1000.0))
            elif kind == "fontWeight":
                lines.append("        static let %s: Font.Weight = %s" % (swift_name(leaf), swift_weight(resolved)))
        lines.append("    }")

    # Тени
    shadows = [(k, v) for k, v in flat.items() if k.startswith("primitive.elevation.")]
    if shadows:
        lines.append("")
        lines.append("    /// Тень в приложении одна на всё. Второй нет — так решено в макете.")
        lines.append("    enum Elevation {")
        lines.append("        struct Shadow: Sendable {")
        lines.append("            let color: Color")
        lines.append("            let radius: CGFloat")
        lines.append("            let x: CGFloat")
        lines.append("            let y: CGFloat")
        lines.append("        }")
        for key, (_t, value, note) in sorted(shadows):
            leaf = key[len("primitive.elevation."):]
            v = resolve(flat, value)
            lines += doc(note, "        ")
            lines.append(
                "        static let %s = Shadow(color: Color(hex: %s).opacity(%g), radius: %g, x: %g, y: %g)"
                % (swift_name(leaf), hex_literal(v["color"]), float(v.get("alpha", 1)),
                   px(v["blur"]), px(v["offsetX"]), px(v["offsetY"]))
            )
        lines.append("    }")

    # Компонентный слой: component.button.primary.background -> Token.Component.Button.Primary.background
    component_keys = [k for k in flat if k.startswith("component.")]
    if component_keys:
        tree = {}
        for key in component_keys:
            parts = key.split(".")[1:]
            node = tree
            for part in parts[:-1]:
                node = node.setdefault(part, {})
            node[parts[-1]] = key

        lines.append("")
        lines.append("    /// Слой компонентов — то, что в Figma лежит свойствами внутри самого")
        lines.append("    /// компонента. Экран сюда не лезет: он выбирает вариант.")
        lines.append("    enum Component {")
        lines += emit_component_tree(tree, flat, "        ", палитра)
        lines.append("    }")

    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def emit_component_tree(tree, flat, indent, палитра):
    lines = []
    for key in sorted(tree):
        node = tree[key]
        if isinstance(node, dict):
            lines.append("%senum %s {" % (indent, pascal(key)))
            lines += emit_component_tree(node, flat, indent + "    ", палитра)
            lines.append("%s}" % indent)
        else:
            token_type, value, note = flat[node]
            resolved = resolve(flat, value)
            lines += doc(note, indent)
            if token_type == "color":
                lines.append("%sstatic let %s = %s" % (indent, camel(key), swift_color(resolved, палитра)))
            elif token_type == "dimension":
                lines.append("%sstatic let %s: CGFloat = %g" % (indent, camel(key), px(resolved)))
    return lines


# ----------------------------------------------------------------- CSS

def emit_css(flat):
    """Четыре блока теми же селекторами, что у пакета Graphite.

    Селекторы взяты у него дословно, а не выдуманы: по ним считает
    контраст `Tools/contrast_graphite.py`, и расхождение в селекторе
    сделало бы наш CSS неизмеримым его инструментом — то есть мы завели
    бы светлую тему, которую нечем проверить.
    """
    blocks = [
        (":root", "dark"),
        ('[data-theme="light"]', "light"),
        ('[data-contrast="high"]', "darkHC"),
        ('[data-theme="light"][data-contrast="high"]', "lightHC"),
    ]
    lines = [
        "/* Сгенерировано Tools/generate_tokens.py. Не редактировать руками. */",
        "/* Те же токены для веб-макета: .dc.html и Figma читают одно и то же. */",
    ]
    for selector, mode in blocks:
        body = []
        for key in sorted(flat):
            token_type, value, _note = flat[key]
            if token_type not in ("color", "dimension", "duration"):
                continue
            resolved = resolve(flat, value)
            name = "--" + key.replace(".", "-")
            if is_modal(resolved):
                # В блок режима попадает только то, что в нём ОТЛИЧАЕТСЯ
                # от тёмной: иначе светлый блок повторит тёмную целиком,
                # и человек не увидит в дифе, что именно меняет тема.
                if mode != "dark" and resolved[mode] == resolved["dark"]:
                    continue
                body.append("  %s: %s;" % (name, resolved[mode]))
            elif mode == "dark":
                body.append("  %s: %s;" % (name, resolved))
        if not body:
            continue
        lines.append("")
        lines.append("%s {" % selector)
        lines += body
        lines.append("}")
    lines.append("")
    return "\n".join(lines)


# --------------------------------------------------------------- Figma

FIGMA_TYPE = {"color": "COLOR", "dimension": "FLOAT", "duration": "FLOAT", "fontWeight": "FLOAT"}

# Имена режимов на той стороне. Взяты у пакета дословно, а не придуманы:
# файл уезжает в ту же Фигму, откуда пришли значения, и свои имена
# режимов сделали бы сверку двух концов невозможной.
FIGMA_MODES = {"dark": "Dark", "light": "Light", "darkHC": "Dark HC", "lightHC": "Light HC"}


def figma_value(token_type, value):
    if token_type == "color":
        v = value.lstrip("#")
        return {
            "r": int(v[0:2], 16) / 255,
            "g": int(v[2:4], 16) / 255,
            "b": int(v[4:6], 16) / 255,
            "a": int(v[6:8], 16) / 255 if len(v) == 8 else 1,
        }
    return px(value)


def emit_figma(flat):
    """Три коллекции переменных — ровно те же три уровня, что и в JSON.
    Semantic и Component ссылаются на Primitive алиасами, а не копируют значения."""
    collections = {"Primitive": [], "Semantic": [], "Component": []}
    for key in sorted(flat):
        token_type, value, note = flat[key]
        if token_type not in FIGMA_TYPE:
            continue
        top = key.split(".")[0]
        collection = {"primitive": "Primitive", "semantic": "Semantic", "component": "Component"}.get(top)
        if collection is None:
            continue
        entry = {
            "name": "/".join(key.split(".")[1:]),
            "type": FIGMA_TYPE[token_type],
            "description": note or "",
        }
        # Режимы спрашиваются ПЕРВЫМИ, и это не вкус порядка.
        # `ALIAS` — это `^\{([^}]+)\}$`, а `str({...})` питоновского
        # словаря тоже начинается с `{` и кончается `}`: проверка на
        # ссылку совпадала со строковым видом словаря режимов и
        # разбирала `'dark': '#F7C75F', …` как путь к токену.
        # Наш класс «вопрос слабее предмета, который он ищет»: регулярка
        # верна, а спрошена о другом предмете.
        m = None if isinstance(value, dict) else ALIAS.match(str(value).strip())
        if m:
            entry["alias"] = "/".join(m.group(1).split(".")[1:])
            entry["aliasCollection"] = {"primitive": "Primitive", "semantic": "Semantic"}[m.group(1).split(".")[0]]
        elif is_modal(value):
            # Все четыре режима, именами пакета Graphite: файл уезжает
            # в ту же Фигму, откуда пришли значения, и разные имена
            # режимов на двух концах сделали бы сверку невозможной.
            entry["values"] = {
                FIGMA_MODES[mode]: figma_value(token_type, value[mode]) for mode in MODES
            }
        else:
            entry["value"] = figma_value(token_type, value)
        collections[collection].append(entry)

    return json.dumps(
        {
            "$generatedBy": "Tools/generate_tokens.py",
            # Было `["Light"]` — ярлык врал, и врал в худшем месте:
            # под ним в Фигму уезжала ТЁМНАЯ палитра целиком
            # (`night1 = #050503` как фон экрана). То есть дизайнер
            # получал тёмные значения, подписанные «светлая».
            #
            # Поправлено 07.10.2026 вместе с заведением четырёх режимов,
            # и ОТДЕЛЬНЫМ коммитом: у этой починки своя цена, и утонуть
            # ей в светлой теме нельзя.
            "modes": [FIGMA_MODES[m] for m in MODES],
            # Почему поле стоит наверху, а не у коллекции. У Фигмы режимы
            # принадлежат КОЛЛЕКЦИИ, а наши три — это СЛОИ
            # (`primitive → semantic → component`), и ось режима к ним
            # ортогональна: один и тот же режим живёт во всех трёх.
            # Прежний ярлык был не просто неверен — он стоял в месте,
            # где по устройству Фигмы его быть не может, и потому
            # не проверялся ничем.
            "$note": "Три коллекции здесь — СЛОИ, а не наборы режимов Фигмы. "
                     "Режимы перечислены сверху и относятся к цветам: "
                     "у цвета `values` по режимам, у размеров и длительностей "
                     "один `value`, годный во всех четырёх.",
            "collections": [
                {"name": name, "variables": items} for name, items in collections.items()
            ],
        },
        ensure_ascii=False,
        indent=2,
    ) + "\n"


# ---------------------------------------------------------------- main

def main():
    raw = load()
    flat = walk(raw, [])

    for path, content in ((SWIFT_OUT, emit_swift(raw, flat)),
                          (CSS_OUT, emit_css(flat)),
                          (FIGMA_OUT, emit_figma(flat))):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        print("→ %s" % os.path.relpath(path, ROOT))

    print("%d токенов" % len(flat))


if __name__ == "__main__":
    main()
