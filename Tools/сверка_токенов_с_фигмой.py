#!/usr/bin/env python3
"""Сверка имён: `DesignTokens/tokens.json` против переменных Figma
(`DesignTokens/ядро-дизайна/tokens/figma-variables.json`).

Адрес сменился 12.10.2026: каталог звался `docs/design-handoff`, и это
имя называло ПРОИСХОЖДЕНИЕ данных (выгрузка дизайна), а не их роль.
Уборка, сносившая выгрузки дизайна, снесла бы вместе с ними вход этой
сверки — и `grep` по имени каталога возражения не нашёл бы, потому
что искать надо было по имени файла.

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
FIGMA_VARS = ROOT / "DesignTokens/ядро-дизайна/tokens/figma-variables.json"

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


def resolve_chain(path: str, by_path: dict[str, tuple]) -> list[str]:
    """Цепочка ссылок до литерала: `component.button.primary.background`
    → `semantic.action.primary` → `primitive.color.arctic`.

    Соответствие слоёв `semantic` и `component` Фигме **выводится
    по этой цепочке, а не угадывается**: у `primitive` фигма-имя уже
    объявлено прозой в `$description`, а semantic на него ссылается.
    Значит пара у semantic — это пара его примитива, и она не выдумана,
    а наследована.

    Цикл в ссылках обрывается: в источнике его быть не должно,
    но молча ходить по кругу инструмент не обязан.
    """
    chain = [path]
    seen = {path}
    while True:
        node = by_path.get(chain[-1])
        if node is None:
            return chain
        value = node[0]
        if not (isinstance(value, str) and value.startswith("{") and value.endswith("}")):
            return chain
        nxt = value[1:-1]
        if nxt in seen:
            chain.append(f"ЦИКЛ→{nxt}")
            return chain
        seen.add(nxt)
        chain.append(nxt)


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
    # Границы имени: точка ПОСЛЕ имени допускается, если за ней не слово.
    # Первая редакция запрещала любую точку справа — и пропускала имя,
    # которым кончается предложение: «…15,53:1. accent.dark.on. БЕЛЫЙ…».
    # Пар выходило 14 вместо настоящих; дефект нашёлся, когда у токена
    # с явно написанным фигма-именем пары не оказалось.
    # Второй объявленный мост: наше описание называет CSS-переменную
    # («togo.css --stock-low»), а у переменной Figma есть поле `css`.
    # Объявлено с ДВУХ сторон, сверяется механически — и закрывает
    # продуктовые цвета, у которых фигма-имени в описании нет.
    by_css = {v["css"]: v for v in fig if v.get("css")}
    for path, value, desc in repo:
        found = None
        for v in by_dotted:
            граница = rf'(?<![\w-])(?<!\.){re.escape(v["dotted"])}(?![\w-])(?!\.\w)'
            if re.search(граница, desc):
                found = v
                break
        if found is None:
            for css in re.findall(r'--[a-z0-9-]+', desc):
                if css in by_css:
                    found = by_css[css]
                    break
        if found is not None:
            pairs.append((path, found, value))
            claimed_repo.add(path)
            claimed_fig.add(found["name"])

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

    # Слои `semantic` и `component`: пара НАСЛЕДУЕТСЯ от примитива
    # по цепочке ссылок. Все 80 листьев этих слоёв заданы ссылками,
    # так что цепочка есть у каждого.
    by_path = {p: (v, d) for p, v, d in repo}
    pair_by_primitive = {path: v for path, v, _ in pairs}
    print("СЛОИ `semantic` И `component` — ПАРА НАСЛЕДУЕТСЯ ПО ЦЕПОЧКЕ")
    print("Фигма-имя объявлено только у `primitive`; semantic на него")
    print("ссылается, значит его пара — пара его примитива. Не выдумана.")
    print()
    print(f"{'наш токен':<42}{'через примитив':<30}Figma")
    print("-" * 100)
    inherited = 0
    orphan_chain: list[tuple[str, str]] = []
    for path, value, _ in repo:
        if not path.startswith(("semantic", "component")):
            continue
        chain = resolve_chain(path, by_path)
        terminal = chain[-1]
        var = pair_by_primitive.get(terminal)
        if var is not None:
            inherited += 1
            print(f"{path:<42}{terminal.replace('primitive.', ''):<30}{var['name']}")
        else:
            orphan_chain.append((path, terminal))
    print("-" * 100)
    print(f"пар наследовано: {inherited} из "
          f"{sum(1 for p, _, _ in repo if p.startswith(('semantic', 'component')))}")
    print()
    print(f"БЕЗ ПАРЫ ДАЖЕ ПО ЦЕПОЧКЕ: {len(orphan_chain)}")
    by_terminal: dict[str, list[str]] = {}
    for path, terminal in orphan_chain:
        by_terminal.setdefault(terminal, []).append(path)
    for terminal in sorted(by_terminal):
        наши = by_terminal[terminal]
        print(f"  {terminal.replace('primitive.', '…'):<34}{len(наши):>3}   "
              f"{', '.join(n.split('.', 1)[1] for n in наши[:4])}"
              f"{' …' if len(наши) > 4 else ''}")
    print()
    print("Читать это так: пара отсутствует не у НАШЕГО имени, а у примитива,")
    print("на который оно ссылается. Объяви фигма-имя у примитива — пара")
    print("появится у всех, кто на него смотрит, разом.")
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
