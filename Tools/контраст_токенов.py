#!/usr/bin/env python3
"""Контраст по токенам ПРИЛОЖЕНИЯ, во всех четырёх режимах.

ЗАЧЕМ ОТДЕЛЬНЫЙ ИНСТРУМЕНТ. `Tools/contrast_graphite.py` печатает свою
границу сам: «это пакет, а не приложение; в репозитории акцент другой».
То есть 124 его пары измерены по CSS-ядру, а `DesignTokens/tokens.json`
— вход Swift — им не измерен ВООБСЕ ни в одной паре. Дефект C-1
(контрол цвета фона экрана в светлой теме) живёт ровно в той щели:
у пакета этой пары нет, потому что у пакета другой акцент и другая
рампа.

ЧТО ОН НЕ МЕРИТ, и это печатается в каждом прогоне, а не хранится
в памяти:

* замер по ЗНАЧЕНИЯМ, не по кадру. «Значение верное, а вызов
  бессильный» он не ловит — `opacity` на тексте, перекрытие цвета
  стилем, контур вместо заливки видны только на пикселе;
* он не знает, НА ЧЁМ лежит элемент. Пары названы руками, и пара,
  которой в списке нет, не проверена — а не «хороша»;
* живых читателей роли он не считает: роль без читателя в Swift
  даёт тот же счёт, что роль на главном экране.

Запуск: python3 Tools/контраст_токенов.py
"""
import json
import os
import re
import sys

КОРЕНЬ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ТОКЕНЫ = os.path.join(КОРЕНЬ, "DesignTokens/tokens.json")
РЕЖИМЫ = ("dark", "light", "darkHC", "lightHC")
ССЫЛКА = re.compile(r"^\{([^}]+)\}$")


def загрузить():
    with open(ТОКЕНЫ, encoding="utf-8") as ф:
        return json.load(ф)


def достать(дерево, путь):
    узел = дерево
    for часть in путь.split("."):
        if not isinstance(узел, dict) or часть not in узел:
            return None
        узел = узел[часть]
    return узел


def значение(дерево, путь, режим, глубина=0):
    """Развернуть ссылку до цвета. Возвращает (цвет, цепь)."""
    if глубина > 12:
        return None, [f"{путь}: ЦИКЛ ССЫЛОК"]
    узел = достать(дерево, путь)
    if узел is None:
        return None, [f"{путь}: НЕТ ТАКОГО ПУТИ"]
    v = узел.get("$value") if isinstance(узел, dict) else None
    if v is None:
        return None, [f"{путь}: нет $value"]
    if isinstance(v, dict):
        if режим not in v:
            return None, [f"{путь}: режима {режим} нет"]
        v = v[режим]
    if isinstance(v, str):
        м = ССЫЛКА.match(v.strip())
        if м:
            цвет, цепь = значение(дерево, м.group(1), режим, глубина + 1)
            return цвет, [путь] + цепь
        return v.strip(), [путь]
    return None, [f"{путь}: значение не строка ({type(v).__name__})"]


def в_rgb(цвет):
    c = цвет.lstrip("#")
    if len(c) == 8:            # RRGGBBAA — альфу здесь НЕ смешиваем
        c = c[:6]
    if len(c) == 3:
        c = "".join(ч * 2 for ч in c)
    if len(c) != 6:
        return None
    try:
        return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        return None


def яркость(rgb):
    def к(к8):
        s = к8 / 255.0
        return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4
    r, g, b = (к(x) for x in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def контраст(a, b):
    ra, rb = в_rgb(a), в_rgb(b)
    if ra is None or rb is None:
        return None
    la, lb = яркость(ra), яркость(rb)
    светлее, темнее = max(la, lb), min(la, lb)
    return (светлее + 0.05) / (темнее + 0.05)


# Пары названы руками и каждая — с осью: ЧТО на ЧЁМ и зачем порог.
# Порог 3.0 для графики (WCAG 1.4.11), 4.5 для текста (1.4.3).
ПАРЫ = [
    ("component.button.secondary.background", "semantic.surface.screen", 3.0,
     "«Гулять» — заливка вторичной кнопки на фоне экрана"),
    ("component.button.secondary.background", "semantic.surface.card", 3.0,
     "та же заливка, если кнопка лежит на карточке"),
    ("component.button.secondary.label",
     "component.button.secondary.background", 4.5,
     "подпись «Гулять» на своей заливке"),
    ("component.button.primary.background", "semantic.surface.screen", 3.0,
     "«Просится» — заливка главной кнопки на фоне экрана"),
    ("component.button.primary.label",
     "component.button.primary.background", 4.5,
     "подпись «Просится» на своей заливке"),
    ("component.button.disabled.background", "semantic.surface.screen", 1.0,
     "выключенная плашка на фоне — порога нет (1.4.11 исключает), ось справочная"),
    ("component.button.destructive.background", "semantic.surface.screen", 3.0,
     "разрушающая кнопка на фоне экрана"),
    ("component.button.destructive.label",
     "component.button.destructive.background", 4.5,
     "подпись разрушающей кнопки"),
    ("semantic.text.primary", "semantic.surface.screen", 4.5,
     "основной текст на фоне экрана"),
    ("semantic.text.primary", "semantic.surface.card", 4.5,
     "основной текст на карточке"),
    ("semantic.text.secondary", "semantic.surface.screen", 4.5,
     "второстепенный текст на фоне экрана"),
    ("semantic.surface.card", "semantic.surface.screen", 3.0,
     "карточка к фону — две поверхности, граница; справочно"),
    ("semantic.surface.control", "semantic.surface.screen", 3.0,
     "КОРЕНЬ C-1: роль «контрол» к роли «фон экрана»"),
    ("semantic.surface.sunken", "semantic.surface.screen", 3.0,
     "утопленная поверхность к фону; справочно"),
]


def main():
    дерево = загрузить()
    провалы = []
    неизмеренные = []
    print("=" * 74)
    print("КОНТРАСТ ПО ТОКЕНАМ ПРИЛОЖЕНИЯ (DesignTokens/tokens.json)")
    print("=" * 74)
    for перёд, зад, порог, ось in ПАРЫ:
        print()
        print(f"· {ось}")
        print(f"  {перёд}")
        print(f"  на {зад}   порог {порог}")
        for режим in РЕЖИМЫ:
            цп, цепь_п = значение(дерево, перёд, режим)
            цз, цепь_з = значение(дерево, зад, режим)
            if цп is None or цз is None:
                причина = цепь_п[-1] if цп is None else цепь_з[-1]
                print(f"    {режим:<8} НЕ ИЗМЕРЕНО — {причина}")
                неизмеренные.append((перёд, зад, режим, причина))
                continue
            k = контраст(цп, цз)
            if k is None:
                print(f"    {режим:<8} НЕ ИЗМЕРЕНО — цвет не разобран "
                      f"({цп} / {цз})")
                неизмеренные.append((перёд, зад, режим, "цвет не разобран"))
                continue
            альфа = ""
            if len(цп.lstrip('#')) == 8 or len(цз.lstrip('#')) == 8:
                альфа = "  ⚠ АЛЬФА ОТБРОШЕНА, число завышено"
            знак = "✔" if k >= порог else "✘"
            if k < порог:
                провалы.append((перёд, зад, режим, k, порог, ось))
            print(f"    {режим:<8} {знак} {k:7.4f}:1   "
                  f"{цп} на {цз}{альфа}")
            if k < 1.05:
                print(f"             ↳ цепь переда: "
                      f"{' → '.join(цепь_п)}")
                print(f"             ↳ цепь зада:   "
                      f"{' → '.join(цепь_з)}")
    print()
    print("=" * 74)
    print(f"ПАР: {len(ПАРЫ)} × {len(РЕЖИМЫ)} режима = "
          f"{len(ПАРЫ) * len(РЕЖИМЫ)} замеров")
    print(f"НЕ ПРОХОДЯТ ПОРОГ: {len(провалы)} · "
          f"НЕ ИЗМЕРЕНО: {len(неизмеренные)}")
    if провалы:
        print()
        print("НЕ ПРОХОДЯТ:")
        for перёд, зад, режим, k, порог, ось in провалы:
            print(f"  {режим:<8} {k:7.4f}:1 (порог {порог})  {ось}")
    print()
    print("ГРАНИЦА ЭТОГО ЗАМЕРА — печатается всегда:")
    print("· замер по ЗНАЧЕНИЯМ, не по кадру: «значение верное, а вызов")
    print("  бессильный» он не ловит — контур вместо заливки, opacity,")
    print("  перекрытие цвета стилем видны только на пикселе;")
    print("· он НЕ знает, на чём элемент лежит на самом деле: пары")
    print("  названы руками, и пара, которой в списке нет, НЕ ПРОВЕРЕНА;")
    print("· альфу он не смешивает с подложкой, а отбрасывает, и говорит")
    print("  об этом в строке: такое число ЗАВЫШЕНО;")
    print("· живых читателей роли он не считает — роль без читателя")
    print("  в Swift даёт тот же счёт, что роль на главном экране.")
    return 1 if провалы else 0


if __name__ == "__main__":
    sys.exit(main())
