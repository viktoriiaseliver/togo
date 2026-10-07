#!/usr/bin/env python3
"""Иллюстрации Togo: источник SVG → два слоя-шаблона в каталоге ассетов.

ЗАЧЕМ ИМЕННО ТАК, А НЕ «ПОЛОЖИТЬ КАРТИНКИ»
===========================================

Замер 07.10.2026 по пакету дизайна «Дневник собаки Togo», окт 2026.
Каждая иллюстрация несёт РОВНО ДВА цвета, и оба — токены:

    stroke="var(--text-secondary)"   контур, ошейник не в счёт
    var(--accent)                     ошейник и предмет

Из этого следует способ переноса, и он не единственный возможный —
поэтому довод записан, а не оставлен в голове:

    способ                        файлов на 8 сцен   смена акцента
    --------------------------------------------------------------
    готовые hex из figma/            16 (dark+light)   16 файлов заново
    то же, но с выбором акцента      48 (×3 акцента)   48 файлов заново
    ДВА СЛОЯ-ШАБЛОНА (здесь)         16                НОЛЬ файлов

Третий столбец и решает. У нового дизайна акцент стал ПЕРЕКЛЮЧАЕМЫМ
(коллекция Figma `Accent`: Indigo · Orange · Pink, см.
`TogoShared/Domain/AccentChoice.swift`), а тем ещё четыре (Dark, Light,
Dark HC, Light HC). Запечённый цвет означал бы 8 × 3 × 4 = 96 картинок
и ручную пересборку при любой правке палитры. Шаблон красится токеном
на отрисовке — и следует за токеном сам.

ЧТО ДЕЛАЕТ
==========

1. Читает источники из `Togo/Resources/Иллюстрации-источник/*.svg`.
2. Срезает `<metadata>` — там манифест C2PA, и это 88 % веса файла
   (8770 байт против 1034 у самой графики в `feed.svg`).
3. Делит каждую сцену на два слоя:
   `<сцена>-line`   — всё, что красится `--text-secondary`;
   `<сцена>-accent` — всё, что красится `--accent`.
   В обоих цвет заменён на `currentColor`, то есть красит вызывающий.
4. Кладёт слои в `Assets.xcassets/Illustrations/` как
   `universal`-шаблоны (`template-rendering-intent: template`).

ГРАНИЦЫ ИНСТРУМЕНТА — печатаются последней строкой
==================================================

Инструмент НЕ проверяет, что рисунок осмыслен: он делит по цвету.
Сцена, где художник покрасил ошейник контурным цветом, уедет целиком
в слой `line`, и это будет видно только кадром.

ЗАЩИТА ОТ МОЛЧАЛИВОГО НУЛЯ
==========================

Сцена без акцентных элементов или без контурных — это не пустой
результат, а поломка разбора: у Togo записано, что сканер, переставший
что-либо находить, молчит так же, как тот, кому нечего сказать.
Поэтому оба слоя обязаны быть непустыми, и общий счёт сверяется
с ожидаемым числом сцен. Иначе выход — ненулевой код.
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Togo" / "Resources" / "Иллюстрации-источник"
CATALOG = ROOT / "Togo" / "Resources" / "Assets.xcassets" / "Illustrations"

# Сцены из пакета дизайна. Список закрыт нарочно: новая сцена — решение,
# а не находка скрипта в каталоге. Так же закрыт список акцентов.
SCENES = ["feed", "treat", "family", "offline", "history", "stock", "onboarding", "paywall"]

ACCENT_TOKEN = "var(--accent)"
LINE_TOKEN = "var(--text-secondary)"

# Элементы, которые могут нести цвет. `g` сюда не входит: группа
# цвета не несёт, она переносит трансформацию, и делить по ней нельзя.
DRAWABLE = r"path|circle|line|rect|ellipse|polyline|polygon"


def strip_metadata(svg: str) -> str:
    """Срезать манифест C2PA. Он не рисует ничего и весит в восемь раз
    больше графики."""
    return re.sub(r"<metadata>.*?</metadata>", "", svg, flags=re.S)


def split_layers(svg: str) -> tuple[str, str, int, int]:
    """Разделить на контурный и акцентный слой.

    Возвращает (line_svg, accent_svg, line_count, accent_count).
    Счётчики — не для отчёта, а для проверки «нашёл не меньше N».
    """
    head = svg[: svg.index(">") + 1]
    body = svg[svg.index(">") + 1 : svg.rindex("</svg>")]

    accent_parts: list[str] = []
    line_parts: list[str] = []
    accent_count = 0
    line_count = 0

    # Разбираем по верхним элементам, сохраняя группы целиком: внутри
    # группы лежит `transform`, и вынутый из неё элемент встанет не там.
    for chunk in re.findall(r"<g\b[^>]*>.*?</g>|<(?:%s)\b[^>]*?/?>(?:</(?:%s)>)?" % (DRAWABLE, DRAWABLE), body, re.S):
        if chunk.startswith("<g"):
            g_head = chunk[: chunk.index(">") + 1]
            inner = chunk[chunk.index(">") + 1 : chunk.rindex("</g>")]
            g_accent, g_line = [], []
            for el in re.findall(r"<(?:%s)\b[^>]*?/?>(?:</(?:%s)>)?" % (DRAWABLE, DRAWABLE), inner, re.S):
                if ACCENT_TOKEN in el:
                    g_accent.append(el)
                else:
                    g_line.append(el)
            if g_accent:
                accent_parts.append(g_head + "".join(g_accent) + "</g>")
                accent_count += len(g_accent)
            if g_line:
                line_parts.append(g_head + "".join(g_line) + "</g>")
                line_count += len(g_line)
        elif ACCENT_TOKEN in chunk:
            accent_parts.append(chunk)
            accent_count += 1
        else:
            line_parts.append(chunk)
            line_count += 1

    def finish(parts: list[str]) -> str:
        out = head + "".join(parts) + "</svg>"
        # Оба токена становятся `currentColor`: цвет задаёт вызывающий.
        out = out.replace(ACCENT_TOKEN, "currentColor").replace(LINE_TOKEN, "currentColor")
        return out

    return finish(line_parts), finish(accent_parts), line_count, accent_count


def write_imageset(name: str, svg: str) -> None:
    folder = CATALOG / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f"{name}.svg").write_text(svg, encoding="utf-8")
    contents = {
        "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {
            "preserves-vector-representation": True,
            "template-rendering-intent": "template",
        },
    }
    (folder / "Contents.json").write_text(
        json.dumps(contents, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


def main() -> int:
    if not SOURCE.is_dir():
        print(f"нет каталога источников: {SOURCE}", file=sys.stderr)
        return 2

    CATALOG.mkdir(parents=True, exist_ok=True)
    (CATALOG / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n", encoding="utf-8"
    )

    broken: list[str] = []
    done = 0
    for scene in SCENES:
        path = SOURCE / f"{scene}.svg"
        if not path.exists():
            broken.append(f"{scene}: источника нет")
            continue
        raw = strip_metadata(path.read_text(encoding="utf-8"))
        line_svg, accent_svg, line_count, accent_count = split_layers(raw)

        # Молчаливый ноль — поломка разбора, а не свойство рисунка.
        if line_count == 0:
            broken.append(f"{scene}: контурный слой пуст")
        if accent_count == 0:
            broken.append(f"{scene}: акцентный слой пуст — ошейник и предмет потеряны")
        if line_count == 0 or accent_count == 0:
            continue

        write_imageset(f"ill-{scene}-line", line_svg)
        write_imageset(f"ill-{scene}-accent", accent_svg)
        done += 1
        print(f"{scene:12} контур {line_count:3}  акцент {accent_count:3}  → ill-{scene}-line, ill-{scene}-accent")

    print()
    if broken:
        for item in broken:
            print("ПОЛОМКА:", item, file=sys.stderr)
        return 1
    if done != len(SCENES):
        print(f"ПОЛОМКА: собрано {done} сцен из {len(SCENES)}", file=sys.stderr)
        return 1

    print(f"Собрано {done} сцен, {done * 2} шаблонов.")
    print("Границы этого инструмента:")
    print("  Делит по цвету, не по смыслу. Ошейник, покрашенный контурным")
    print("  цветом, уедет в слой контура — это видно только кадром.")
    print("  Про сцену, которой нет в SCENES, инструмент не знает вовсе:")
    print("  список закрыт, новая сцена добавляется решением.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
