#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Того · схема зеркала SwiftData для CloudKit, выведенная из моделей.

Зачем. Типы `CD_*` заводит само зеркало — при первой записи объекта и
только в среде development. Значит их нельзя ни выложить файлом, ни
получить без живого Apple ID… так считалось. Замер 23.09.2026 показал
другое: правило, по которому зеркало превращает поле модели в поле
записи, **выводится из уже заведённых типов** и воспроизводит их
побайтно. Пять живых зеркал, 75 полей, ноль расхождений.

Отсюда этот файл: он строит описание `CD_*` для всех моделей
`TogoSchemaV3` по тому же правилу, и схему можно выложить импортом,
не запуская приложение.

    python3 Tools/derive_cloudkit_mirror.py                  # проверить правило
    python3 Tools/derive_cloudkit_mirror.py --schema > f.ckdb  # собрать схему

ПРАВИЛО, выведенное из выгрузки (`cktool export-schema`):

    String, String?, UUID, перечисление через `…Raw`, связь «к одному»
                                 → STRING QUERYABLE SEARCHABLE SORTABLE
    Date, Date?                  → TIMESTAMP QUERYABLE SORTABLE
    Int, Int?, Bool              → INT64 QUERYABLE SORTABLE
    Double, Double?              → DOUBLE QUERYABLE SORTABLE
    [String], [Int]              → BYTES QUERYABLE SORTABLE
    связь «ко многим»            → поля нет вовсе
    плюс всегда                  → CD_entityName STRING QUERYABLE SEARCHABLE SORTABLE

Чего правило НЕ знает: как зеркало кладёт `Data` (фото собаки, снимок
документа). Живого образца нет — ни одно такое поле в CloudKit ещё
не заводилось, и угадывать нельзя: ASSET и BYTES ведут себя по-разному,
а поле потом не переделать. Эти поля скрипт называет вслух и пропускает.

Вычисляемые свойства не зеркалятся: их в хранилище нет. Отличаются
тем, что за типом идёт `{`, — так же, как их отличает компилятор.
"""

import re
import sys
import pathlib

КОРЕНЬ = pathlib.Path(__file__).resolve().parent.parent

ТИПЫ = {
    'String': 'STRING QUERYABLE SEARCHABLE SORTABLE',
    'UUID':   'STRING QUERYABLE SEARCHABLE SORTABLE',
    'Date':   'TIMESTAMP QUERYABLE SORTABLE',
    'Int':    'INT64 QUERYABLE SORTABLE',
    'Bool':   'INT64 QUERYABLE SORTABLE',
    'Double': 'DOUBLE QUERYABLE SORTABLE',
}
МАССИВ = 'BYTES QUERYABLE SORTABLE'
ССЫЛКА = ТИПЫ['String']

СИСТЕМНЫЕ = [
    '"___createTime" TIMESTAMP',
    '"___createdBy"  REFERENCE',
    '"___etag"       STRING',
    '"___modTime"    TIMESTAMP',
    '"___modifiedBy" REFERENCE',
    '"___recordID"   REFERENCE',
]
ПРАВА = ['GRANT WRITE TO "_creator"', 'GRANT CREATE TO "_icloud"', 'GRANT READ TO "_world"']


def модели_схемы():
    """Список моделей берётся из источника, а не из головы."""
    src = (КОРЕНЬ / 'TogoShared/Domain/SchemaVersions.swift').read_text(encoding='utf-8')
    блок = re.search(r'static var models:\s*\[any PersistentModel\.Type\]\s*\{\s*\[(.*?)\]',
                     src, re.S)
    if not блок:
        sys.exit('не нашёл список моделей в SchemaVersions.swift')
    имена = re.findall(r'(\w+)\.self', блок.group(1))
    if len(имена) < 2:
        sys.exit(f'список моделей прочитался как {имена} — проверка не состоялась')
    return имена


def поля_модели(тело):
    """Хранимые свойства и их форма в CloudKit. `None` — форма неизвестна."""
    поля = []
    строки = тело.splitlines()
    for i, стр in enumerate(строки):
        # Атрибут может стоять в той же строке: `@Attribute(.externalStorage)
        # var image: Data?`. Первая редакция этого не видела и молча
        # пропускала поле — ровно тот дефект, против которого весь скрипт.
        м = re.match(r'    (?:@\w+\([^)]*\)\s+)?var (\w+): ([\w\[\]?<>, ]+?)\s*(=|$)', стр)
        if not м:
            continue
        хвост = стр[м.end(2):].strip()
        if хвост.startswith('{'):
            continue                                  # вычисляемое
        if not хвост and i + 1 < len(строки) and строки[i + 1].strip().startswith('{'):
            continue                                  # вычисляемое, скобка на следующей строке
        if i and '@Transient' in строки[i - 1]:
            continue
        поле, тип = м.group(1), м.group(2).strip()
        голый = тип.rstrip('?')
        if голый.startswith('['):
            внутри = голый[1:-1].rstrip('?')
            поля.append((поле, МАССИВ if внутри in ТИПЫ else None))   # связь «ко многим»
        elif голый in ТИПЫ:
            поля.append((поле, ТИПЫ[голый]))
        elif голый == 'Data':
            поля.append((поле, None))                 # форма не выведена
        else:
            поля.append((поле, ССЫЛКА))               # связь «к одному»
    return поля


def все_модели():
    найдено = {}
    for p in (КОРЕНЬ / 'TogoShared/Models').glob('*.swift'):
        src = p.read_text(encoding='utf-8')
        for m in re.finditer(r'final class (\w+)[^{]*\{(.*?)\n\}', src, re.S):
            найдено[m.group(1)] = поля_модели(m.group(2))
    return найдено


def запись(имя, поля):
    строки = [f'CD_{п:<26} {т}' for п, т in sorted(поля) if т]
    строки.append(f'CD_{"entityName":<26} {ТИПЫ["String"]}')
    строки = sorted(строки)
    тело = ',\n    '.join(строки + СИСТЕМНЫЕ + ПРАВА)
    return f'RECORD TYPE CD_{имя} (\n    {тело}\n);\n'


def сверка(выгрузка):
    """Доказательство правила: вывести уже существующие типы и сравнить."""
    модели = все_модели()
    расхождений = 0
    не_заведено_всего = 0
    for имя in sorted(set(re.findall(r'RECORD TYPE CD_(\w+) \(', выгрузка))):
        m = re.search(rf'RECORD TYPE CD_{имя} \((.*?)\)\s*;', выгрузка, re.S)
        живые = {}
        for строка in m.group(1).splitlines():
            строка = строка.strip().rstrip(',')
            if not строка or строка.startswith(('GRANT', '"___')):
                continue
            части = строка.split(None, 1)
            живые[части[0]] = ' '.join(части[1].split())
        мои = {f'CD_{п}': т for п, т in модели.get(имя, []) if т}
        мои['CD_entityName'] = ТИПЫ['String']
        плохие = [(k, v, мои.get(k, 'нет поля')) for k, v in живые.items() if мои.get(k) != v]
        расхождений += len(плохие)
        не_заведены = sorted(set(мои) - set(живые))
        не_заведено_всего += len(не_заведены)
        знак = '✓' if not плохие and not не_заведены else '✗'
        print(f'{знак} CD_{имя}: живых полей {len(живые)}, расхождений {len(плохие)}, '
              f'правило знает ещё {len(не_заведены)}')
        for поле, живое, моё in плохие[:5]:
            print(f'      {поле}: в CloudKit «{живое}», по правилу «{моё}»')
        if не_заведены:
            print('       не заведены в CloudKit:',
                  ', '.join(x[3:] for x in не_заведены))
    return расхождений, не_заведено_всего


if __name__ == '__main__':
    if '--schema' in sys.argv:
        модели = все_модели()
        куски = []
        неизвестные = []
        for имя in модели_схемы():
            поля = модели.get(имя)
            if поля is None:
                sys.exit(f'модель {имя} из TogoSchemaV3 не найдена в TogoShared/Models')
            неизвестные += [f'{имя}.{п}' for п, т in поля
                            if т is None and not п.endswith('Storage')]
            куски.append(запись(имя, поля))
        if неизвестные:
            print('# ВНИМАНИЕ: форма этих полей не выведена и они пропущены:',
                  file=sys.stderr)
            for п in неизвестные:
                print(f'#   {п}', file=sys.stderr)
        print('\n'.join(куски))
    else:
        выгрузка = sys.stdin.read() if not sys.stdin.isatty() else ''
        if not выгрузка:
            sys.exit('Подай выгрузку на вход:\n'
                     '  xcrun cktool export-schema --team-id … --container-id … '
                     '--environment development | python3 Tools/derive_cloudkit_mirror.py')
        расхождений, не_заведено = сверка(выгрузка)
        print(f'\nИТОГО расхождений: {расхождений}, полей не заведено: {не_заведено}')
        # Поля зеркала заводит только запись из приложения со значением.
        # Молчать о них нельзя: до 23.09 скрипт говорил «все шестнадцать
        # зеркал на месте», когда у CD_Dog не хватало десяти полей —
        # номера чипа, телефона врача, целевого веса.
        sys.exit(1 if (расхождений or не_заведено) else 0)
