#!/usr/bin/env python3
"""Сверка библиотеки компонентов хендоффа (`.d.ts`) с нашими вью.

Предмет — **имена и контракты**, а не вид: по решению Виктории 07.10
дизайн и тексты переезжают в Figma, а логика и токены остаются. Значит
вопрос не «похоже ли нарисовано», а «есть ли у каждого компонента
дизайна носитель в коде и сходятся ли пропсы с нашим доменом».

`.d.ts` — это контракт: имя компонента, имена пропсов, их типы
и обязательность. Он сильнее картинки и сильнее таблицы токенов:
токены говорят, каким цветом, контракт — какие данные нужны.

Пути задаются ключом, а не записаны внутрь: хендофф лежит ВНЕ git
(`~/Projects/.хранилище-вне-git/…`), и ссылка на него стареет.
Отчёт первой строкой печатает, что именно прочитано.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Наш префикс дизайн-системы. Выводится из дерева, а не задаётся числом:
# см. `известные_вью`.
PREFIX = "TG"

# Порог «было что сверять». Числа — с редакции v3 15:01.
MIN_CONTRACTS = 80


def contracts(root: pathlib.Path) -> list[dict]:
    """Компоненты из `.d.ts`: имя, группа, пропсы.

    Разбор по интерфейсу `<Имя>Props`, а не по всему файлу: в файле
    бывают вспомогательные интерфейсы (`DoseChange`), и считать их
    пропсами компонента значило бы ошибиться в сторону полноты.
    """
    out = []
    for path in sorted(root.rglob("*.d.ts")):
        text = path.read_text(encoding="utf-8", errors="replace")
        # `Badge.d.ts` → stem даёт `Badge.d`, а интерфейс зовётся
        # `BadgeProps`. Первая редакция искала `Badge.dProps`,
        # не находила НИ ОДНОГО и напечатала бы девяносто строк
        # «пропсов ноль» — порог «было что сверять» это остановил.
        name = path.name.removesuffix(".d.ts")
        # Интерфейс ищется по имени файла, а если его нет — берётся
        # первый `*Props` в файле, и расхождение имён называется вслух.
        # `MediaCell.d.ts` объявляет `MediaGridProps` и функцию
        # `MediaGrid`: имя файла компоненту не равно, и молча считать
        # такой файл беспропсовым значило бы потерять компонент.
        # Объявленных функций в файле бывает несколько: компонент плюс
        # ВЫЧИСЛЕНИЯ (`labDeviation`, `sampleMark`). Имя компонента
        # берётся от файла, а не от первой функции: первая бывает
        # вспомогательной, и так в список компонентов попал `scoreLevel`.
        declared_all = re.findall(r'export declare function\s+(\w+)', text)
        declared = re.match(r'(\w+)', name) if name in declared_all else None
        m = re.search(rf'interface\s+{re.escape(name)}Props\s*\{{(.*?)\}}',
                      text, re.S)
        renamed = None
        if not m:
            alt = re.search(r'interface\s+(\w+)Props\s*\{(.*?)\}', text, re.S)
            if alt:
                renamed = alt.group(1)
                m = alt
        body = m.group(len(m.groups())) if m else ""
        props = []
        # Поля разделяются `;`, а не переводом строки: девять контрактов
        # записаны одной строкой целиком, и разбор по строкам дал у них
        # ноль пропсов — круглое число на девяти файлах подряд.
        for chunk in re.split(r'[;\n]', body):
            chunk = chunk.strip()
            if not chunk or chunk.startswith(("/*", "*", "//")):
                continue
            chunk = re.sub(r'/\*.*?\*/', '', chunk).strip()
            pm = re.match(r'(\w+)(\?)?\s*:\s*(.+)$', chunk)
            if pm:
                props.append({
                    "name": pm.group(1),
                    "optional": bool(pm.group(2)),
                    "type": pm.group(3).strip(),
                })
        out.append({
            "name": name,
            "file": name,
            "logic": [f for f in declared_all if f != name],
            "group": path.parent.name,
            "props": props,
            "has_props_interface": bool(m),
            "renamed": renamed if renamed and renamed != name else None,
            "helpers": sorted(set(re.findall(r'interface\s+(\w+)', text))
                              - {f"{name}Props"}),
        })
    return out


def swift_types() -> set[str]:
    """Имена наших struct/enum/class — из дерева, а не списком руками."""
    found: set[str] = set()
    out = subprocess.run(
        ["grep", "-rhoE", r"(struct|enum|final class|class) [A-Za-z_][A-Za-z0-9_]*",
         "--include=*.swift", "Togo", "TogoShared"],
        cwd=ROOT, capture_output=True, text=True,
    ).stdout
    for line in out.splitlines():
        found.add(line.split()[-1])
    return found


def counterpart(name: str, swift: set[str]) -> tuple[str | None, str]:
    """Носитель в коде. Проверяются только НАЗВАННЫЕ формы имени —
    догадки по смыслу не делаются: `Chip` и `TGCheckRow` могут быть
    одним по роли и разным по контракту, и решать это замером нельзя."""
    for cand, how in ((f"{PREFIX}{name}", "префикс дизайн-системы"),
                      (name, "имя целиком"),
                      (f"{name}View", "суффикс View"),
                      (f"{name}Screen", "суффикс Screen")):
        if cand in swift:
            return cand, how
    return None, "—"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--handoff", required=True,
                    help="корень редакции хендоффа (в нём каталог components/)")
    ap.add_argument("--group", default=None, help="только эта группа")
    args = ap.parse_args()

    root = pathlib.Path(args.handoff).expanduser()
    comps = contracts(root / "components")
    head = subprocess.run(["git", "--no-optional-locks", "rev-parse", "--short", "HEAD"],
                          cwd=ROOT, capture_output=True, text=True).stdout.strip()

    print(f"хендофф   {root}")
    print(f"код       {ROOT}   HEAD {head}")
    print(f"контрактов {len(comps)} в {len({c['group'] for c in comps})} группах")
    print()

    if len(comps) < MIN_CONTRACTS:
        print("Я ОСЛЕП — контрактов меньше ожидаемого, списки не называю:")
        print(f"  разобрано {len(comps)}, ждал ≥{MIN_CONTRACTS}")
        return 2

    no_iface = [c["name"] for c in comps if not c["has_props_interface"]]
    if len(no_iface) > len(comps) // 4:
        print("Я ОСЛЕП — у четверти с лишним контрактов не нашёлся интерфейс")
        print(f"  {len(no_iface)} из {len(comps)}: {', '.join(no_iface[:8])}")
        return 2

    swift = swift_types()
    rows = [dict(c, **dict(zip(("code", "how"), counterpart(c["name"], swift))))
            for c in comps]
    if args.group:
        rows = [r for r in rows if r["group"] == args.group]

    print(f"{'группа':<14}{'компонент':<20}{'пропсов':>8}{'обяз.':>7}   носитель в коде")
    print("-" * 82)
    by_group: dict[str, list[dict]] = {}
    for r in rows:
        by_group.setdefault(r["group"], []).append(r)
    paired = 0
    for group, items in by_group.items():
        for r in items:
            req = sum(1 for p in r["props"] if not p["optional"])
            mark = r["code"] or "— НЕТ"
            if r["code"]:
                paired += 1
            print(f"{group:<14}{r['name']:<20}{len(r['props']):>8}{req:>7}   {mark}")
    print("-" * 82)
    print(f"носитель найден у {paired} из {len(rows)}")
    print()

    print("ЧЕГО ЭТА СВЕРКА НЕ ВИДИТ:")
    print("  · роль: компонент может существовать под другим именем, и это")
    print("    не выводится ни из имени, ни из типа — только человеком")
    print("  · сходятся ли ПРОПСЫ с нашим доменом: сверяются имена")
    print("    компонентов, а совпадение полей надо читать глазами")
    print("  · вид: контракт говорит, какие данные нужны, и молчит о том,")
    print("    как нарисовано; кадр это не заменяет")
    print(f"  · носителем считается только названная форма имени "
          f"({PREFIX}X · X · XView · XScreen)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
