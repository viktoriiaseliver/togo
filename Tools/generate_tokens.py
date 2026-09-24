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
    ("primitive.space", "Space", "dimension", "Шаг сетки. Прикладной код берёт Spacing, а не это."),
    ("primitive.size", "Size", "dimension", "Размеры контролов и иконок."),
    ("primitive.font.size", "FontSize", "dimension", "Кегли."),
    ("primitive.font.weight", "FontWeight", "fontWeight", "Начертания."),
    ("primitive.duration", "Duration", "duration", "Длительности анимаций."),
]

WEIGHT_MAP = {400: ".regular", 500: ".medium", 600: ".semibold", 700: ".bold",
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
                lines.append("        static let %s = Color(hex: %s)" % (swift_name(leaf), hex_literal(resolved)))
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
        lines += emit_component_tree(tree, flat, "        ")
        lines.append("    }")

    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def emit_component_tree(tree, flat, indent):
    lines = []
    for key in sorted(tree):
        node = tree[key]
        if isinstance(node, dict):
            lines.append("%senum %s {" % (indent, pascal(key)))
            lines += emit_component_tree(node, flat, indent + "    ")
            lines.append("%s}" % indent)
        else:
            token_type, value, note = flat[node]
            resolved = resolve(flat, value)
            lines += doc(note, indent)
            if token_type == "color":
                lines.append("%sstatic let %s = Color(hex: %s)" % (indent, camel(key), hex_literal(resolved)))
            elif token_type == "dimension":
                lines.append("%sstatic let %s: CGFloat = %g" % (indent, camel(key), px(resolved)))
    return lines


# ----------------------------------------------------------------- CSS

def emit_css(flat):
    lines = [
        "/* Сгенерировано Tools/generate_tokens.py. Не редактировать руками. */",
        "/* Те же токены для веб-макета: .dc.html и Figma читают одно и то же. */",
        ":root {",
    ]
    for key in sorted(flat):
        token_type, value, _note = flat[key]
        if token_type not in ("color", "dimension", "duration"):
            continue
        resolved = resolve(flat, value)
        name = "--" + key.replace(".", "-")
        if token_type == "color":
            lines.append("  %s: %s;" % (name, resolved))
        else:
            lines.append("  %s: %s;" % (name, resolved))
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


# --------------------------------------------------------------- Figma

FIGMA_TYPE = {"color": "COLOR", "dimension": "FLOAT", "duration": "FLOAT", "fontWeight": "FLOAT"}


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
        m = ALIAS.match(str(value).strip())
        if m:
            entry["alias"] = "/".join(m.group(1).split(".")[1:])
            entry["aliasCollection"] = {"primitive": "Primitive", "semantic": "Semantic"}[m.group(1).split(".")[0]]
        else:
            entry["value"] = figma_value(token_type, value)
        collections[collection].append(entry)

    return json.dumps(
        {
            "$generatedBy": "Tools/generate_tokens.py",
            "modes": ["Light"],
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
