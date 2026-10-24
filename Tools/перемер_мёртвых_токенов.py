#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Перемер живости токенов. Временный инструмент, 24.10.2026.

Живость = вызов по имени в .swift вне Generated/, В КОДЕ, не в прозе.
Комментарии вырезаются до счёта: сторож, их не вырезающий, меряет прозу
(оплачено у ComponentTokenScopeTests, см. его голову).

Два конца у каждого токена меряются ПОРОЗНЬ и в ОДНОМ прогоне:
  объявление — из Tokens.generated.swift
  вызов      — из остального дерева
плюс отрицательный контроль (имени нет вовсе) и положительный
(заведомо живой), оба в этом же прогоне.
"""
from __future__ import annotations
import os
import re
import sys

КОРЕНЬ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ГЕНЕРАТ = os.path.join(КОРЕНЬ, "TogoShared", "Generated", "Tokens.generated.swift")
ДЕРЕВО = ["Togo", "TogoShared", "TogoWidgets", "TogoTests", "TogoUITests", "Дизайн"]


def без_комментариев(текст: str) -> str:
    """Строго слева направо, посимвольно.

    ПОЧЕМУ НЕ ПОСТРОЧНО «сперва /*, потом //»: эта форма съедает файл
    целиком начиная с первого `Togo/DesignSystem/**` в доккомментарии —
    `/**` читается как открытие блока, который не закрывается никогда.
    Замер 24.10.2026: КиноЭкран.swift 19 108 байт → 1 429 «кода»,
    и четыре живых вызова токенов пропали из счёта. Слева направо
    строка `///` съедается как строчный комментарий ПЕРВОЙ, и до `/**`
    разбор не доходит.

    ТОТ ЖЕ ДЕФЕКТ ЖИВ В `ComponentTokenScopeTests.безКомментариев`
    (TogoTests/ComponentTokenScopeTests.swift:56) — тот же порядок,
    то же дерево, 11 файлов с `/*` в Togo/TogoShared/TogoWidgets.
    """
    вне = []
    i, n = 0, len(текст)
    глубина = 0
    в_строке = False
    while i < n:
        c = текст[i]
        двое = текст[i:i + 2]
        if глубина > 0:
            if двое == "*/":
                глубина -= 1
                i += 2
                continue
            if двое == "/*":
                глубина += 1
                i += 2
                continue
            if c == "\n":
                вне.append(c)
            i += 1
            continue
        if в_строке:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                в_строке = False
            вне.append(c)
            i += 1
            continue
        if c == '"':
            в_строке = True
            вне.append(c)
            i += 1
            continue
        if двое == "//":
            while i < n and текст[i] != "\n":
                i += 1
            continue
        if двое == "/*":
            глубина = 1
            i += 2
            continue
        вне.append(c)
        i += 1
    return "".join(вне)


def объявления() -> list:
    """Полные пути токенов из сгенерированного файла."""
    текст = без_комментариев(open(ГЕНЕРАТ, encoding="utf-8").read())
    стек = []
    пути = []
    глубина_enum = []
    for строка in текст.split("\n"):
        м = re.search(r"\b(?:nonisolated\s+)?(?:fileprivate\s+)?(?:struct|enum)\s+([A-Za-zА-Яа-я_][A-Za-zА-Яа-я0-9_]*)", строка)
        if м and "{" in строка:
            стек.append(м.group(1))
            глубина_enum.append(строка.count("{") - строка.count("}"))
            continue
        л = re.search(r"\bstatic\s+let\s+([A-Za-zА-Яа-я_][A-Za-zА-Яа-я0-9_]*)", строка)
        if л and стек:
            пути.append(".".join(стек + [л.group(1)]))
        # закрытие области
        закр = строка.count("}") - строка.count("{")
        for _ in range(закр):
            if стек:
                стек.pop()
                глубина_enum.pop()
    return пути


def код_дерева() -> dict:
    файлы = {}
    for каталог in ДЕРЕВО:
        корневой = os.path.join(КОРЕНЬ, каталог)
        for папка, _, имена in os.walk(корневой):
            if "/Generated/" in папка + "/" or папка.endswith("/Generated"):
                continue
            for имя in имена:
                if not имя.endswith(".swift"):
                    continue
                путь = os.path.join(папка, имя)
                try:
                    текст = open(путь, encoding="utf-8").read()
                except Exception:
                    continue
                файлы[os.path.relpath(путь, КОРЕНЬ)] = без_комментариев(текст)
    return файлы


def считать(имя: str, файлы: dict) -> list:
    """Вхождения `имя`, НЕ являющиеся префиксом более длинного имени."""
    шаблон = re.compile(re.escape(имя) + r"(?![A-Za-zА-Яа-я0-9_])")
    места = []
    for путь, текст in файлы.items():
        for i, строка in enumerate(текст.split("\n"), 1):
            for _ in шаблон.finditer(строка):
                места.append("%s:%d" % (путь, i))
    return места


def главное():
    пути = объявления()
    файлы = код_дерева()
    # Общие — внутренний слой дедупликации, не токен для экранов.
    пути = [п for п in пути if not п.startswith("Token.Общие.")]
    пути = [п for п in пути if п.startswith("Token.")]

    живые, мёртвые = {}, {}
    for п in пути:
        места = считать(п, файлы)
        if места:
            живые[п] = места
        else:
            мёртвые[п] = []

    print("ФАЙЛОВ ПРОСМОТРЕНО: %d" % len(файлы))
    print("ТОКЕНОВ ОБЪЯВЛЕНО:  %d" % len(пути))
    print("ЖИВЫХ (есть вызов): %d" % len(живые))
    print("БЕЗ ЧИТАТЕЛЯ:       %d" % len(мёртвые))
    print()
    print("--- КОНТРОЛЬ, снят в этом же прогоне ---")
    for имя, ожидание in [("Token.Space.s8", "заведомо живой"),
                          ("Token.Surface.card", "заведомо живой"),
                          ("Token.Space.s1", "ПРЕФИКСНАЯ ловушка: такого токена нет"),
                          ("Token.ТакогоТокенаНетВовсе", "отрицательный контроль")]:
        print("  %-34s %-34s %d" % (имя, ожидание, len(считать(имя, файлы))))
    print()
    if len(sys.argv) > 1 and sys.argv[1] == "--список":
        print("--- БЕЗ ЧИТАТЕЛЯ, по группам ---")
        for п in sorted(мёртвые):
            print("  " + п)
        print()
        print("--- ЖИВЫЕ: имя и число вызовов ---")
        for п in sorted(живые, key=lambda x: -len(живые[x])):
            print("  %-52s %d" % (п, len(живые[п])))


if __name__ == "__main__":
    главное()
