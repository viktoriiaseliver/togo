#!/usr/bin/env python3
"""Сверка имён: `DesignTokens/tokens.json` против переменных Figma
из хендоффа (`docs/design-handoff/design/tokens/figma-variables.json`).

Это сверка ИМЁН, а не значений. Значения поколений разные нарочно —
в репозитории лайм, в пакете индиго, — и смена поколения решается
Викторией, а не этим скриптом.

**Пары не выдумываются.** Берутся только объявленные:

  со стороны репозитория   `$description` токена называет фигма-имя
                           прозой: «Фон экрана. color.bg.page, режим Dark»
  со стороны пакета        поле `css` называет имя CSS-переменной

Совпадение по значению используется ТОЛЬКО как перепроверка уже
найденной пары и никогда как основание её завести: один и тот же hex
стоит у разных ролей, и пара по цвету — это пара по совпадению.
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REPO_TOKENS = ROOT / "DesignTokens/tokens.json"
FIGMA_VARS = ROOT / "docs/design-handoff/design/tokens/figma-variables.json"

# Порог «было что сверять». Числа — с коммита 65e6401; меньше —
# разбор ослеп, и список «пары нет» читать нельзя.
MIN_REPO_LEAVES = 150
MIN_FIGMA_VARS = 180


def leaves(node, path=""):
    """Листья DTCG: путь → (значение, описание). Ключи на `$` — служебные."""
    out = []
    if isinstance(node, dict):
        if "$value" in node:
            return [(path, node["$value"], node.get("$description", ""))]
        for key, value in node.items():
            if key.startswith("$"):
                continue
            out += leaves(value, f"{path}.{key}" if path else key)
    return out


def figma_variables(data):
    out = []
    for collection in data["collections"]:
        for v in collection["variables"]:
            out.append({
                "collection": collection["name"],
                "modes": collection["modes"],
                "name": v["name"],
                "dotted": v["name"].replace("/", "."),
                "css": v.get("css"),
                "type": v.get("type"),
                "values": v.get("values", {}),
            })
    return out


def main() -> int:
    repo = leaves(json.loads(REPO_TOKENS.read_text(encoding="utf-8")))
    data = json.loads(FIGMA_VARS.read_text(encoding="utf-8"))
    fig = figma_variables(data)

    print(f"репозиторий   {REPO_TOKENS.relative_to(ROOT)}   листьев {len(repo)}")
    print(f"пакет         {FIGMA_VARS.relative_to(ROOT)}   переменных {len(fig)}"
          f" в {len(data['collections'])} коллекциях")
    print()

    if len(repo) < MIN_REPO_LEAVES or len(fig) < MIN_FIGMA_VARS:
        print("Я ОСЛЕП — разобрано меньше ожидаемого, списки не называю:")
        print(f"  листьев {len(repo)} (ждал ≥{MIN_REPO_LEAVES}), "
              f"переменных {len(fig)} (ждал ≥{MIN_FIGMA_VARS})")
        return 2

    # Пара объявлена, если дотошное имя переменной Figma встречается
    # в описании токена репозитория. Ищем самое длинное совпадение,
    # иначе `color.fill.1` поймается внутри `color.fill.12`.
    by_dotted = sorted(fig, key=lambda v: -len(v["dotted"]))
    pairs: list[tuple[str, dict, str]] = []
    claimed_repo: set[str] = set()
    claimed_fig: set[str] = set()
    for path, value, desc in repo:
        for v in by_dotted:
            if re.search(rf'(?<![\w.-]){re.escape(v["dotted"])}(?![\w.-])', desc):
                pairs.append((path, v, value))
                claimed_repo.add(path)
                claimed_fig.add(v["name"])
                break

    print(f"ПАР ПО ОБЪЯВЛЕНИЮ: {len(pairs)}")
    print(f"{'репозиторий':<34}{'Figma':<26}{'коллекция':<10} значение")
    print("-" * 86)
    for path, v, value in pairs:
        same = ""
        if v["type"] == "COLOR" and isinstance(value, str):
            hits = {m for m, x in v["values"].items()
                    if isinstance(x, str) and x.lower() == value.lower()}
            same = f"  = {sorted(hits)}" if hits else "  ≠ поколение"
        print(f"{path:<34}{v['name']:<26}{v['collection']:<10} {value}{same}")
    print()

    no_pair_repo = [(p, val) for p, val, _ in repo if p not in claimed_repo]
    no_pair_fig = [v for v in fig if v["name"] not in claimed_fig]

    print(f"БЕЗ ПАРЫ В РЕПОЗИТОРИИ: {len(no_pair_repo)} листьев")
    layers: dict[str, list[str]] = {}
    for path, _ in no_pair_repo:
        layers.setdefault(path.split(".")[0], []).append(path)
    for layer, items in sorted(layers.items()):
        print(f"  {layer:<12}{len(items):>4}   {', '.join(i.split('.', 1)[1] for i in items[:6])}"
              f"{' …' if len(items) > 6 else ''}")
    print()

    print(f"БЕЗ ПАРЫ В ПАКЕТЕ: {len(no_pair_fig)} переменных")
    cols: dict[str, list[dict]] = {}
    for v in no_pair_fig:
        cols.setdefault(v["collection"], []).append(v)
    for col, items in sorted(cols.items()):
        no_css = sum(1 for v in items if not v["css"])
        print(f"  {col:<12}{len(items):>4}   без объявленного css: {no_css}")
    print()

    print("КОЛЛЕКЦИИ ПАКЕТА — объём, который придётся переносить:")
    total_cells = 0
    for c in data["collections"]:
        cells = len(c["variables"]) * len(c["modes"])
        total_cells += cells
        print(f"  {c['name']:<12}{len(c['variables']):>4} × {len(c['modes'])} режим(ов)"
              f" = {cells:>4} значений   {' · '.join(c['modes'])}")
    print(f"  {'ВСЕГО':<12}{'':>4}   {'':>12} {total_cells:>4} значений")
    print()

    print("ЧЕГО ЭТА СВЕРКА НЕ ВИДИТ:")
    print("  · пару, которую никто не объявил: она не выдумывается ни по")
    print("    имени, ни по значению — один hex стоит у разных ролей")
    print("  · верна ли сама объявленная пара: описание — это утверждение")
    print("    автора токена, и стареет оно молча")
    print("  · значения: поколения разные нарочно (лайм против индиго),")
    print("    и «≠ поколение» в таблице — не дефект, а ожидаемое")
    print("  · светлую тему: в репозитории её нет структурно, поэтому")
    print("    у режимов Light / Dark HC / Light HC пары быть не может")
    return 0


if __name__ == "__main__":
    sys.exit(main())
