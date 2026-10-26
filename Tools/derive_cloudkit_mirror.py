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
последней версии схемы по тому же правилу, и схему можно выложить импортом,
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
    """Список моделей — из ПОСЛЕДНЕЙ версии схемы, а не из первой.

    Прежняя редакция брала `re.search` по всему файлу, то есть первое
    вхождение `static var models` — а это `TogoSchemaV1`. В комментарии
    при этом было написано «из TogoSchemaV3». Работало по случайности:
    набор моделей во всех версиях один, и различие их списков ни на что
    не влияло. Замечено 23.09.2026, когда версий стало четыре.

    Ровно та же болезнь, что у сторожа, меряющего собственную копию
    числа: инструмент утверждал не то, что читал, и не мог об этом
    сказать.
    """
    src = (КОРЕНЬ / 'TogoShared/Domain/SchemaVersions.swift').read_text(encoding='utf-8')
    версии = re.findall(
        r'enum TogoSchemaV(\d+): VersionedSchema \{.*?'
        r'static var models:\s*\[any PersistentModel\.Type\]\s*\{\s*\[(.*?)\]',
        src, re.S)
    if not версии:
        sys.exit('не нашёл ни одной версии схемы в SchemaVersions.swift')
    номер, блок = max(версии, key=lambda пара: int(пара[0]))
    имена = re.findall(r'(\w+)\.self', блок)
    if len(имена) < 2:
        sys.exit(f'список моделей V{номер} прочитался как {имена} — проверка не состоялась')
    return имена


def поля_модели(тело, классы=frozenset()):
    """Хранимые свойства и их форма в CloudKit. `None` — форма неизвестна.

    `классы` — имена `final class` из `TogoShared/Models`, то есть
    настоящий признак связи «ко многим». До 26.10.2026 его тут не было,
    и массив разбирался **по прокси**: `МАССИВ if внутри in ТИПЫ else
    None`, то есть «элемент — не примитив» читалось как «это связь».

    Замер 26.10.2026 на живой выгрузке: правило дало ровно одно
    расхождение, `CD_Medication.CD_doseSlotsData` — «в CloudKit BYTES
    QUERYABLE SORTABLE, по правилу нет поля». Разбор двадцати полей,
    попадающих в эту ветку:

        19 штук   [LogEvent]?, [DoseRecord]?, [CareTask]? …
                  элемент — @Model-КЛАСС, это и есть связь «ко многим»
         1 штука  [DoseSlot] — `nonisolated struct DoseSlot: Codable,
                  Hashable, Sendable` (Care.swift:712), ЗНАЧЕНИЕ.
                  SwiftData кладёт такой массив байтами, и CloudKit
                  это подтверждает: BYTES QUERYABLE SORTABLE — ровно
                  константа `МАССИВ` этого же файла

    То есть **правило отстало, а поле из обмена не выбывало**:
    `SharedDiaryRecords` пишет `record["doseSlotsData"]` и читает его
    обратно, оба конца живы. Говорить «поля нет вовсе» про значение,
    которое лежит в облаке, — это сторож на прокси: ось «не примитив»
    удовлетворяется и связью, и структурой, а значат они обратное.

    Теперь спрашивается предмет: элемент — зеркалимый класс или нет.
    Следствие на будущее: любое новое поле вида `[КакаяТоСтруктура]`
    будет выведено байтами, а не пропущено молча.
    """
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
            # Связь «ко многим» — только массив ЗЕРКАЛИМОГО КЛАССА.
            # Массив значений (примитив или Codable-структура) зеркало
            # кладёт байтами.
            поля.append((поле, None if внутри in классы else МАССИВ))
        elif голый in ТИПЫ:
            поля.append((поле, ТИПЫ[голый]))
        elif голый == 'Data':
            поля.append((поле, None))                 # форма не выведена
        else:
            поля.append((поле, ССЫЛКА))               # связь «к одному»
    return поля


def все_модели():
    # Два прохода нарочно: признак связи «ко многим» — имя КЛАССА,
    # а оно может быть объявлено в файле, который разбирается позже.
    # Одним проходом `[Prescription]?` у `Clinic` разобралось бы иначе,
    # чем у `Dog`, в зависимости от порядка `glob` — то есть результат
    # зависел бы от имён файлов.
    тела = {}
    for p in sorted((КОРЕНЬ / 'TogoShared/Models').glob('*.swift')):
        src = p.read_text(encoding='utf-8')
        for m in re.finditer(r'final class (\w+)[^{]*\{(.*?)\n\}', src, re.S):
            тела[m.group(1)] = m.group(2)
    классы = frozenset(тела)
    if len(классы) < 10:
        sys.exit(f'классов модели прочитано {len(классы)} — разбор не состоялся, '
                 'это ответ про регулярку, а не про код')
    return {имя: поля_модели(тело, классы) for имя, тело in тела.items()}


def запись(имя, поля):
    строки = [f'CD_{п:<26} {т}' for п, т in sorted(поля) if т]
    строки.append(f'CD_{"entityName":<26} {ТИПЫ["String"]}')
    строки = sorted(строки)
    тело = ',\n    '.join(строки + СИСТЕМНЫЕ + ПРАВА)
    return f'RECORD TYPE CD_{имя} (\n    {тело}\n);\n'


def сверка(выгрузка):
    """Доказательство правила: вывести ожидаемые типы и сравнить.

    **Ось идёт от СХЕМЫ ПРИЛОЖЕНИЯ, а не от выгрузки — правка 14.10.2026,
    и до неё сверка молчала ровно там, где дыра самая большая.**

    Прежде цикл шёл по `RECORD TYPE CD_*`, найденным в выгрузке. Тип,
    которого в контейнере нет вовсе, в цикл не попадал — то есть
    не попадал и в отчёт. Замер: приложение знает 21 модель, в выгрузке
    16 типов `CD_*`, в отчёте 16 строк, и о пяти моделях медслоя
    (`Clinic`, `LabResult`, `VetVisit`, `Diagnosis`, `Prescription`)
    не сказано ни слова. Итог при этом печатался как «расхождений 0,
    полей не заведено 23» — и читался как «типы в порядке, не хватает
    только полей».

    > **Проверка не может покраснеть на том, чего её ось не называет.**
    > Здесь осью была выгрузка — то есть проверка спрашивала контейнер
    > о том, что в нём есть, и получала согласие по построению.

    Это тот же класс, за который 14.10 переписали ворота общего дневника
    (`deploy_cloudkit_schema.sh`): там эталоном был файл на два типа.
    Один и тот же дефект в двух проверках подряд — не совпадение,
    а привычка брать ось у того, кого спрашиваешь.
    """
    модели = все_модели()
    расхождений = 0
    не_заведено_всего = 0
    нет_типа = []
    for имя in sorted(модели_схемы()):
        m = re.search(rf'RECORD TYPE CD_{имя} \((.*?)\)\s*;', выгрузка, re.S)
        if m is None:
            поля = [п for п, т in модели.get(имя, []) if т]
            нет_типа.append((имя, len(поля)))
            не_заведено_всего += len(поля)
            print(f'✗ CD_{имя}: ТИПА НЕТ В КОНТЕЙНЕРЕ ВОВСЕ, '
                  f'правило знает {len(поля)} полей')
            continue
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
    if нет_типа:
        print(f'\nТИПОВ НЕТ ВОВСЕ: {len(нет_типа)} — '
              + ', '.join(f'{и} ({n})' for и, n in нет_типа))
        print('Это НЕ лечится файлом схемы: тип `CD_*` заводит зеркало '
              'SwiftData\nпервой записью объекта СО ЗНАЧЕНИЕМ, '
              'и только в development.')
    return расхождений, не_заведено_всего


# ─── Типы общего дневника ───────────────────────────────────────────────
#
# `CD_*` заводит зеркало SwiftData. Типы общего дневника (`Dog`,
# `LogEvent`, `CareTask`, `Medication`, `DoseRecord` в зоне `family`)
# пишет наш собственный код через `CKRecord`, и у них своя форма:
# ключ записи — это ключ, который ставит `SharedDiaryRecords.apply`.
#
# Выводятся они отсюда же и по той же причине, что и зеркало: список
# полей, написанный руками, знает только то, что в него положили. Поле,
# добавленное в снимок и забытое в схеме, молча не уедет в production —
# и обнаружится тем, что у второго человека его просто нет.

СНИМКИ = {'Dog': 'DogPayload', 'CareTask': 'CarePayload',
          'Medication': 'MedicationPayload', 'DoseRecord': 'DosePayload',
          'LogEvent': 'EventPayload'}

ФОРМА_СНИМКА = {
    'String': 'STRING', 'UUID': 'STRING', 'Date': 'TIMESTAMP',
    'Int': 'INT64', 'Bool': 'INT64', 'Double': 'DOUBLE',
    '[Int]': 'LIST<INT64>', '[String]': 'LIST<STRING>',
}


def поля_снимка(имя):
    src = (КОРЕНЬ / 'TogoShared/Sync/SharedDiary.swift').read_text(encoding='utf-8')
    тело = re.search(r'struct %s: Equatable, Sendable, Codable \{(.*?)\n\}' % имя, src, re.S)
    if not тело:
        sys.exit(f'снимок {имя} не найден в SharedDiary.swift')
    поля = {m.group(1): m.group(2).strip()
            for m in re.finditer(r'var (\w+): ([^\n=]+)', тело.group(1))}
    if len(поля) < 3:
        sys.exit(f'снимок {имя} прочитался как {поля} — разбор не состоялся')
    return поля


def запись_общего(тип, снимок):
    src = (КОРЕНЬ / 'TogoShared/Sync/SharedDiaryRecords.swift').read_text(encoding='utf-8')
    блок = re.search(r'static func apply\(_ payload: %s, to record: CKRecord\) \{(.*?)\n    \}'
                     % снимок, src, re.S)
    if not блок:
        sys.exit(f'не нашёл apply для {снимок}')
    ключи = re.findall(r'record\["(\w+)"\] = payload\.(\w+)', блок.group(1))
    if not ключи:
        sys.exit(f'у {снимок} не прочитался ни один ключ записи')
    поля = поля_снимка(снимок)
    строки = []
    for ключ, свойство in ключи:
        тип_swift = поля.get(свойство)
        if тип_swift is None:
            sys.exit(f'{тип}.{свойство} есть в записи и нет в снимке')
        форма = ФОРМА_СНИМКА.get(тип_swift.rstrip('?'))
        if форма is None:
            sys.exit(f'{тип}.{свойство}: не знаю, как хранить {тип_swift} — угадывать нельзя')
        строки.append((ключ, форма))
    # Зеркало кладёт их само; у своих записей они тоже есть.
    строки += [('createdTimestamp', 'TIMESTAMP'), ('modifiedTimestamp', 'TIMESTAMP')]

    ширина = max(len(k) for k, _ in строки) + 2
    ширина = max(ширина, len('"___modifiedBy"') + 2)
    куски = [f'    RECORD TYPE {тип} (']
    for имя, форма in [('"___createTime"', 'TIMESTAMP'), ('"___createdBy"', 'REFERENCE'),
                       ('"___etag"', 'STRING'), ('"___modTime"', 'TIMESTAMP'),
                       ('"___modifiedBy"', 'REFERENCE'), ('"___recordID"', 'REFERENCE')]:
        куски.append(f'        {имя:<{ширина}} {форма},')
    for имя, форма in sorted(строки):
        куски.append(f'        {имя:<{ширина}} {форма},')
    куски += ['        GRANT WRITE TO "_creator",',
              '        GRANT CREATE TO "_icloud",',
              '        GRANT READ TO "_world"',
              '    );']
    return '\n'.join(куски)


if __name__ == '__main__':
    if '--schema' in sys.argv:
        модели = все_модели()
        куски = []
        неизвестные = []
        for имя in модели_схемы():
            поля = модели.get(имя)
            if поля is None:
                sys.exit(f'модель {имя} из последней версии схемы не найдена в TogoShared/Models')
            неизвестные += [f'{имя}.{п}' for п, т in поля
                            if т is None and not п.endswith('Storage')]
            куски.append(запись(имя, поля))
        if неизвестные:
            print('# ВНИМАНИЕ: форма этих полей не выведена и они пропущены:',
                  file=sys.stderr)
            for п in неизвестные:
                print(f'#   {п}', file=sys.stderr)
        for тип, снимок in sorted(СНИМКИ.items()):
            куски.append(запись_общего(тип, снимок))
        print('\n\n'.join(куски))
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
