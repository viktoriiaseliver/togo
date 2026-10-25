#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Опись имён SF Symbols в исходниках Togo.

Несуществующее имя символа даёт **пустое место, а не ошибку сборки**
(записано в голове `RootView`), поэтому проверять его может только
такой обход либо кадр.

ТРИ ПРОХОДА, намеренно разные — каждый следующий ловит то, мимо чего
проходит предыдущий:

  A — литерал стоит ПРЯМО у метки `systemName:`/`systemImage:`.
      Не видит ничего, что приезжает переменной.
  B — ВСЕ строковые литералы дерева, отобранные по ФОРМЕ имени
      символа. Ловит `enum Значок`, массивы, словари, плечи тернарника.
      Не видит имён, не похожих на символ: `add_a_photo` (Material,
      подчёркивания вместо точек) мимо этого фильтра проходит молча.
  C — литералы в объявлениях, НАЗВАННЫХ значком (`symbol`, `значок`,
      `icon`, `systemImage`, `glyph`). Отбор по МЕСТУ, а не по виду —
      форма имени тут не важна вовсе.

Каждое имя сверяется с каталогом рантайма (`name_availability.plist`
из CoreGlyphs симулятора): есть ли оно вовсе и с какой версии iOS.
Сверять надо и версию: имя, заведённое позже `IPHONEOS_DEPLOYMENT_TARGET`,
на старой системе тоже даёт пустое место.

**Контроль печатается в том же запуске** и закрывает три ветки
вердикта — «есть», «позже цели», «нет в каталоге». Ветка, которая
не срабатывает ни разу, неотличима от сломанной.

Запуск:  python3 Tools/значки-опись.py <корень репозитория>
"""
from __future__ import annotations
import os
import plistlib
import re
import sys

КАТАЛОГ = ("/Library/Developer/CoreSimulator/Volumes/iOS_23F77/Library/Developer/"
           "CoreSimulator/Profiles/Runtimes/iOS 26.5.simruntime/Contents/Resources/"
           "RuntimeRoot/System/Library/PrivateFrameworks/SFSymbols.framework/"
           "CoreGlyphs.bundle")

# «год» каталога -> минимальная iOS, где имя уже есть
ГОД_В_IOS = {
    "2019": 13.0, "2019.1": 13.1,
    "2020": 14.0, "2020.1": 14.2, "2020.2": 14.5, "2020.3": 14.5,
    "2021": 15.0, "2021.1": 15.1, "2021.2": 15.2, "2021.3": 15.4,
    "2022": 16.0, "2022.1": 16.1, "2022.2": 16.1, "2022.3": 16.4,
    "2023": 17.0, "2023.1": 17.0, "2023.2": 17.0, "2023.3": 17.4,
    "2024": 18.0, "2024.1": 18.0, "2024.2": 18.1, "2024.3": 18.2, "2024.4": 18.4,
    "2025": 26.0, "2025.1": 26.0, "2025.2": 26.1, "2025.3": 26.2,
}
ЦЕЛЬ = 17.0  # IPHONEOS_DEPLOYMENT_TARGET

ФОРМА = re.compile(r"^[a-z0-9]+(?:\.[a-z0-9]+)+$")  # минимум одна точка
ОДНОСЛОВНЫЕ = {  # имена символов без точки — список замкнутый, иначе шум
    "pawprint", "heart", "star", "calendar", "clock", "gear", "gearshape",
    "person", "photo", "camera", "bell", "bolt", "drop", "flame", "house",
    "pills", "pill", "syringe", "stethoscope", "cross", "bandage", "scissors",
    "figure", "dog", "cat", "leaf", "moon", "sun", "sparkles", "trash",
    "plus", "minus", "xmark", "checkmark", "chevron", "arrow", "ellipsis",
    "magnifyingglass", "link", "lock", "key", "map", "pin", "tag", "bag",
    "cart", "creditcard", "doc", "folder", "book", "bookmark", "paperplane",
    "envelope", "phone", "message", "bubble", "mic", "speaker", "video",
    "play", "pause", "stop", "record", "shuffle", "repeat", "square",
    "circle", "triangle", "diamond", "hexagon", "shield", "flag", "crown",
    "medal", "trophy", "gift", "balloon", "party", "wand", "eye", "hand",
    "ear", "nose", "mouth", "brain", "lungs", "waveform", "thermometer",
    "scalemass", "ruler", "hammer", "wrench", "screwdriver", "paintbrush",
    "pencil", "highlighter", "eraser", "scribble", "signature", "slider",
    "switch", "power", "wifi", "antenna", "network", "icloud", "externaldrive",
    "internaldrive", "opticaldiscdrive", "tv", "display", "laptopcomputer",
    "desktopcomputer", "keyboard", "printer", "scanner", "faxmachine",
    "sdcard", "esim", "simcard", "memorychip", "cpu", "server", "xserve",
    "airplane", "car", "bus", "tram", "cablecar", "ferry", "sailboat",
    "bicycle", "scooter", "stroller", "fuelpump", "parkingsign", "crop",
    "exclamationmark", "questionmark", "info", "number", "percent", "sum",
    "function", "textformat", "bold", "italic", "underline", "strikethrough",
    "list", "text", "note", "pawprint", "takeoutbag", "fork", "cup",
    "mug", "wineglass", "birthday", "carrot", "fish", "bird", "lizard",
    "tortoise", "hare", "ant", "ladybug", "teddybear", "globe", "location",
    "safari", "compass", "binoculars", "backpack", "tent", "mountain",
    "beach", "umbrella", "snowflake", "cloud", "wind", "tornado", "hurricane",
    "rainbow", "water", "humidity", "aqi", "sunrise", "sunset", "sleep",
    "bed", "shower", "bathtub", "toilet", "washer", "dryer", "oven",
    "microwave", "refrigerator", "sink", "chair", "sofa", "lamp", "fan",
    "air", "poweroutlet", "lightbulb", "ellipses", "pawprint",
}

ЯКОРИ = ("systemName:", "systemImage:", "systemSymbol:")

ПРОПУСК_КАТАЛОГОВ = {".git", "build", "DerivedData", ".build", "Pods"}


def каталог_символов():
    путь = os.path.join(КАТАЛОГ, "name_availability.plist")
    with open(путь, "rb") as ф:
        данные = plistlib.load(ф)
    символы = данные["symbols"]
    алиасы = {}
    путь_а = os.path.join(КАТАЛОГ, "name_aliases.strings")
    if os.path.exists(путь_а):
        try:
            with open(путь_а, "rb") as ф:
                алиасы = plistlib.load(ф)
        except Exception:
            алиасы = {}
    return символы, алиасы


def все_свифт(корень):
    for путь, каталоги, файлы in os.walk(корень):
        каталоги[:] = [к for к in каталоги if к not in ПРОПУСК_КАТАЛОГОВ]
        for имя in файлы:
            if имя.endswith(".swift"):
                yield os.path.join(путь, имя)


ЛИТЕРАЛ = re.compile(r'"([^"\\\n]*)"')


def похоже_на_символ(s: str) -> bool:
    if not s or len(s) > 90:
        return False
    if ФОРМА.match(s):
        return True
    if s in ОДНОСЛОВНЫЕ:
        return True
    return False


def проход_A(строка: str):
    """литералы, стоящие прямо у якоря"""
    итог = []
    for якорь in ЯКОРИ:
        поз = 0
        while True:
            i = строка.find(якорь, поз)
            if i < 0:
                break
            поз = i + len(якорь)
            хвост = строка[поз:поз + 120]
            м = re.match(r'\s*"([^"\\\n]*)"', хвост)
            if м:
                итог.append(("литерал", м.group(1)))
            else:
                м2 = re.match(r'\s*([^,)\n]+)', хвост)
                итог.append(("НЕ-ЛИТЕРАЛ", (м2.group(1).strip() if м2 else "?")))
    return итог


def проход_C(корень, символы):
    """Структурный проход: литералы в объявлениях, НАЗВАННЫХ значком.

    Проходы A и B отбирают по ВИДУ строки. Имя Material `add_a_photo`
    такой фильтр не ловит вовсе — подчёркивания вместо точек. Значит
    третий отбор идёт не по виду, а по МЕСТУ.
    """
    имя_объявления = re.compile(
        r"\b(?:var|let|func|static\s+let|static\s+var)\s+"
        r"([A-Za-zА-Яа-я_][A-Za-zА-Яа-я0-9_]*)")
    маркер = re.compile(r"symbol|значок|значк|icon|systemimage|glyph|иконк",
                        re.IGNORECASE)
    найдено = {}
    объявлений = 0
    for путь in все_свифт(корень):
        отн = os.path.relpath(путь, корень)
        with open(путь, encoding="utf-8") as ф:
            строки = ф.read().split("\n")
        i = 0
        while i < len(строки):
            стр = строки[i]
            if стр.strip().startswith("//"):
                i += 1
                continue
            м = имя_объявления.search(стр)
            if not (м and маркер.search(м.group(1))):
                i += 1
                continue
            объявлений += 1
            баланс, начало, открывалось = 0, i, False
            while i < len(строки):
                т = строки[i]
                без = re.sub(r'"[^"\\\n]*"', '""', т)
                баланс += без.count("{") - без.count("}")
                if без.count("{"):
                    открывалось = True
                for л in ЛИТЕРАЛ.finditer(т):
                    if л.group(1):
                        найдено.setdefault(л.group(1), []).append("%s:%d" % (отн, i + 1))
                i += 1
                if открывалось and баланс <= 0:
                    break
                if not открывалось and i > начало:
                    break
                if i - начало > 200:
                    break
    return объявлений, найдено


def главная():
    корень = sys.argv[1] if len(sys.argv) > 1 else "."
    символы, алиасы = каталог_символов()

    A = {}   # имя -> [адреса]
    A_нелитерал = []
    B = {}   # имя -> [адреса]

    for путь in все_свифт(корень):
        отн = os.path.relpath(путь, корень)
        with open(путь, encoding="utf-8") as ф:
            строки = ф.read().split("\n")
        for н, строка in enumerate(строки, 1):
            голая = строка.strip()
            if голая.startswith("//") or голая.startswith("///"):
                continue
            for вид, значение in проход_A(строка):
                if вид == "литерал":
                    A.setdefault(значение, []).append("%s:%d" % (отн, н))
                else:
                    A_нелитерал.append(("%s:%d" % (отн, н), значение, голая[:150]))
            for м in ЛИТЕРАЛ.finditer(строка):
                s = м.group(1)
                if похоже_на_символ(s):
                    B.setdefault(s, []).append("%s:%d" % (отн, н))

    def вердикт(имя):
        if имя in символы:
            год = символы[имя]
            ios = ГОД_В_IOS.get(год, 99.0)
            if ios > ЦЕЛЬ:
                return "ПОЗЖЕ ЦЕЛИ (с iOS %.1f, каталог %s)" % (ios, год)
            return "есть"
        if имя in алиасы:
            наст = алиасы[имя]
            return "АЛИАС -> %s" % наст
        return "НЕТ В КАТАЛОГЕ"

    print("=" * 78)
    print("ПРОХОД A — литерал прямо у systemName:/systemImage:")
    print("=" * 78)
    плохие_A = []
    for имя in sorted(A):
        в = вердикт(имя)
        if в != "есть":
            плохие_A.append((имя, в, A[имя]))
    print("всего разных имён: %d, негодных: %d" % (len(A), len(плохие_A)))
    for имя, в, адреса in плохие_A:
        print("  ✗ %-44s %s" % (имя, в))
        for а in адреса:
            print("        %s" % а)

    print()
    print("=" * 78)
    print("ПРОХОД A2 — у якоря стоит НЕ литерал (имя приезжает со стороны)")
    print("=" * 78)
    print("мест: %d" % len(A_нелитерал))
    for адрес, выражение, текст in A_нелитерал:
        print("  • %-38s %s" % (выражение[:38], адрес))
        print("        %s" % текст)

    print()
    print("=" * 78)
    print("ПРОХОД B — ВСЕ литералы по форме имени символа")
    print("=" * 78)
    только_B = [и for и in B if и not in A]
    print("всего по форме: %d, из них НЕ видел проход A: %d"
          % (len(B), len(только_B)))
    плохие_B = []
    for имя in sorted(только_B):
        в = вердикт(имя)
        if в != "есть":
            плохие_B.append((имя, в, B[имя]))
    print()
    print("--- НОВЫЕ годные имена, которых проход A не видел ---")
    for имя in sorted(только_B):
        if вердикт(имя) == "есть":
            print("  ✓ %-44s %s" % (имя, ", ".join(B[имя][:3])))
    print()
    print("--- по форме похоже на символ, но в каталоге НЕТ (или позже цели) ---")
    for имя, в, адреса in плохие_B:
        print("  ? %-44s %s" % (имя, в))
        for а in адреса[:4]:
            print("        %s" % а)

    print()
    print("=" * 78)
    print("ПРОХОД C — литералы в объявлениях, НАЗВАННЫХ значком")
    print("=" * 78)
    объявлений, C = проход_C(корень, символы)
    плохие_C = [(и, вердикт(и), а) for и, а in sorted(C.items())
                if вердикт(и) != "есть"]
    print("объявлений: %d, разных литералов: %d, НЕ символов каталога: %d"
          % (объявлений, len(C), len(плохие_C)))
    for имя, в, адреса in плохие_C:
        print("  ✗ %-40s %s" % (имя[:40], в))
        for а in sorted(set(адреса))[:4]:
            print("        %s" % а)

    # контроль: заведомо существующее и заведомо несуществующее имя
    print()
    print("=" * 78)
    print("КОНТРОЛЬ инструмента (в том же замере)")
    print("=" * 78)
    for проба, ожидание in (("heart.fill", "есть"),
                            # контроль ветки «позже цели»: SF Symbols 6 / iOS 18
                            ("arrow.trianglehead.clockwise", "ПОЗЖЕ ЦЕЛИ"),
                            # имя Material из ответов дизайна — у нас его быть не может
                            ("add_a_photo", "НЕТ В КАТАЛОГЕ"),
                            ("такого.символа.нет.вовсе", "НЕТ В КАТАЛОГЕ")):
        факт = вердикт(проба)
        знак = "OK" if факт.startswith(ожидание[:6]) else "!! РАСХОЖДЕНИЕ"
        print("  %-28s ждал «%s», получил «%s»  %s" % (проба, ожидание, факт, знак))
    print("  размер каталога: %d имён" % len(символы))


if __name__ == "__main__":
    главная()
