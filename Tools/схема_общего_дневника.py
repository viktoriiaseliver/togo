#!/usr/bin/env python3
"""Что общий дневник пишет в CloudKit — выведено из кода, не из файла.

    python3 Tools/схема_общего_дневника.py            # таблица для человека
    python3 Tools/схема_общего_дневника.py --json     # для сверки скриптом

**Зачем этот файл появился 14.10.2026.** Ворота приёмки схемы
(`Tools/deploy_cloudkit_schema.sh`) сверяли production с
`CloudKit/schema.ckdb`, а тот описывает **два** типа — `LogEvent`
и `DoseRecord`. Код к этому дню писал **двенадцать**. То есть ворота
говорили «в production есть всё из файла» и были правы, а вопрос,
на который их звали, был другой: «есть ли в production всё, что пишет
код». Эталон отстал на двадцать дней, и заметить это по зелёному было
нельзя ничем.

> **Сверка с рукописным эталоном отвечает про эталон.** Чтобы она
> отвечала про код, эталон надо выводить из кода.

Поэтому здесь не копия и не список, а **разбор**: единственный источник
— `TogoShared/Sync/SharedDiaryRecords.swift`, где присвоение
`record["поле"] = …` и есть отправка поля в CloudKit, и
`TogoShared/Sync/SharedDiary.swift`, где `enum RecordType` даёт имена
типов. Ни одного имени поля здесь не записано руками: запишешь — и эта
копия разойдётся с кодом ровно так же, как разошёлся `schema.ckdb`.

**Чего этот разбор НЕ делает.** Он не знает типов значений
(`STRING`/`TIMESTAMP`/`INT64`), потому что в месте присвоения их нет:
`record["grams"] = payload.grams` не говорит, что `grams` целое.
Выводить тип отсюда значило бы угадывать, а угаданный тип в файле
схемы молчит до первой записи. Поэтому инструмент отвечает только
на вопрос «какие ПОЛЯ каких ТИПОВ ЗАПИСЕЙ код отправляет» — и ворота
строятся на нём, а не на догадке.

**Приёмка встроена, и это не украшение.** Разбор регулярками — тот
самый класс, который в этом проекте врал чаще всего: `grep` без
`--no-ignore-files` даёт ложный ноль, сторож полей моделей считал
уровень тела класса нулевым и находил ноль полей у всех. Пустой ответ
и «нечего отправлять» здесь неотличимы на глаз, поэтому инструмент
**падает**, если результат выглядит вырожденным: нет всех типов из
`enum RecordType`, или у какого-то типа ноль полей. Отказ называет,
что именно не сошлось, а не печатает пустую таблицу.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RECORDS = os.path.join(ROOT, "TogoShared/Sync/SharedDiaryRecords.swift")
DIARY = os.path.join(ROOT, "TogoShared/Sync/SharedDiary.swift")


def читать(path):
    if not os.path.exists(path):
        sys.exit(f"нет файла {path} — замер не состоялся, это ответ про путь, а не про код")
    with open(path, encoding="utf-8") as f:
        return f.read()


def типы_записей(text):
    """`case dog = "Dog"` → {"dog": "Dog"}. Только внутри enum RecordType.

    **Закомментированные строки отбрасываются, и за это уже заплачено
    в первом же прогоне этого файла.** В `RecordType` лежит снятый
    08.10 `// case member = "FamilyMember"` с объяснением, почему его
    не надо заводить обратно. Разбор без этой строки нашёл тринадцать
    типов вместо двенадцати и объявил `FamilyMember` пропавшим
    из production — то есть **предъявил счёт за намеренно снятое**.

    Поймала собственная приёмка этого файла, а не чтение: вырожденный
    результат она называет, а не печатает.
    """
    начало = text.find("enum RecordType")
    if начало < 0:
        sys.exit("в SharedDiary.swift не найден `enum RecordType` — замер не состоялся")
    # Конец перечисления — первая строка, закрывающая его тело.
    хвост = text[начало:]
    конец = хвост.find("\n    }")
    тело = хвост[:конец if конец > 0 else len(хвост)]
    живые = [s for s in тело.splitlines() if not s.lstrip().startswith(("//", "///"))]
    return dict(re.findall(r'case (\w+) = "(\w+)"', "\n".join(живые)))


def тело_функции(text, начало):
    """От `{` после сигнатуры до парной `}`. Счётом скобок, не отступом.

    Отступ врёт: `final class X {` уже открыла скобку, и разбор
    по уровню отступа однажды дал ноль полей у всех моделей сразу.
    """
    i = text.find("{", начало)
    if i < 0:
        return ""
    глубина = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            глубина += 1
        elif text[j] == "}":
            глубина -= 1
            if глубина == 0:
                return text[i + 1:j]
    return ""


def поля_по_снимку(text):
    """`apply(_ payload: XPayload, to record:)` → поля, которые он пишет."""
    out = {}
    for m in re.finditer(r"static func apply\(_ payload: (\w+), to record: CKRecord\)", text):
        тело = тело_функции(text, m.end())
        out[m.group(1)] = sorted(set(re.findall(r'record\["(\w+)"\]\s*=', тело)))
    return out


def снимок_по_типу(text, кейсы):
    """`record(_ payload: XPayload…)` + `RecordType.<кейс>` → XPayload → имя типа."""
    out = {}
    for m in re.finditer(r"static func record\(_ payload: (\w+)", text):
        тело = тело_функции(text, m.end())
        найден = re.search(r"SharedDiary\.RecordType\.(\w+)\.rawValue", тело)
        if найден and найден.group(1) in кейсы:
            out[m.group(1)] = кейсы[найден.group(1)]
    return out


def собрать():
    записи = читать(RECORDS)
    кейсы = типы_записей(читать(DIARY))
    поля = поля_по_снимку(записи)
    тип_по_снимку = снимок_по_типу(записи, кейсы)

    схема = {}
    for снимок, имя in тип_по_снимку.items():
        if снимок in поля:
            схема[имя] = поля[снимок]

    # Приёмка. Пустой ответ и «нечего отправлять» на глаз неотличимы.
    беды = []
    пропали = sorted(set(кейсы.values()) - set(схема))
    if пропали:
        беды.append("типы объявлены в RecordType, но разбор их не нашёл: " + ", ".join(пропали))
    for имя, список in sorted(схема.items()):
        if not список:
            беды.append(f"{имя}: ноль полей — разбор не состоялся")
    if беды:
        sys.exit("ЗАМЕР НЕ СОСТОЯЛСЯ:\n  " + "\n  ".join(беды))

    return схема


def main():
    схема = собрать()
    if "--json" in sys.argv:
        print(json.dumps(схема, ensure_ascii=False, sort_keys=True, indent=2))
        return
    всего = 0
    for имя in sorted(схема):
        поля = схема[имя]
        всего += len(поля)
        print(f"{имя} ({len(поля)})")
        print("    " + " · ".join(поля))
    print(f"\nтипов {len(схема)}, полей {всего} — выведено из "
          f"TogoShared/Sync/SharedDiaryRecords.swift")


if __name__ == "__main__":
    main()
