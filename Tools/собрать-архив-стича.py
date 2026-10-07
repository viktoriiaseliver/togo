#!/usr/bin/env python3
"""Сборка архива Togo из медкнижки Стича — всё по-русски.

    python3 Tools/собрать-архив-стича.py <куда.togo>

ЭТО ПРОМЕЖУТОЧНЫЙ АРХИВ. Он несёт только то, что ложится на существующие
снимки без новых моделей. Приложение после него сносить НЕЛЬЗЯ — чего в нём
нет, перечислено внутри самого файла и отдельным эпизодом, который будет
виден на экране после загрузки.

Проверяется не глазами: /tmp/bk/decode собран из настоящего BackupArchive.swift
и либо принимает файл, либо отказывает.

ЛОВУШКА ДАТ. В CSV из Google Sheets даты приехали серийными числами Excel:
45824.0 — это 16.06.2025, отсчёт от 1899-12-30. Прочитать как число —
получить молчаливую чушь, а не отказ.
"""
import csv, json, os, pathlib, sys, datetime as dt

# Данные в git, СЫРЬЁ СНАРУЖИ: таблицы выгружены из Google Sheets и лежат
# в хранилище вне git. Путь переопределяется переменной ТАБЛИЦЫ.
TBL = pathlib.Path(os.environ.get('ТАБЛИЦЫ') or os.path.expanduser(
    '~/Projects/.хранилище-вне-git/Togo/медкнижка-стича-2026-10-07/'
    'таблица-анализов-и-рецептов'))
EXCEL_EPOCH = dt.date(1899, 12, 30)

# Отсутствие сырья обязано быть ОТКАЗОМ, а не пустым архивом.
# 07.10.2026 скрипт искал таблицы рядом с собой, не нашёл и собрал файл
# из одного предупреждения — молча, с кодом 0. Пустой результат, который
# выглядит как успех, и есть то, что мы ловим весь день.
НУЖНЫ = ['Все анализы.csv', 'Рецепты.csv', 'Щитовидная железа.csv', 'Пробелы.csv']
нет = [n for n in НУЖНЫ if not (TBL / n).exists()]
if нет:
    sys.exit(f"нет таблиц в {TBL}:\n  " + "\n  ".join(нет) +
             "\nпуть задаётся переменной ТАБЛИЦЫ")


def excel_date(v):
    """Серийное число Excel -> дата. Пустое или нечисловое -> None."""
    s = str(v).strip()
    if not s or s == '—':
        return None
    try:
        return EXCEL_EPOCH + dt.timedelta(days=float(s))
    except ValueError:
        return None


def iso(d, h=12, m=0):
    if d is None:
        return None
    return dt.datetime(d.year, d.month, d.day, h, m).strftime('%Y-%m-%dT%H:%M:%SZ')


def num(v):
    s = str(v).strip().replace(',', '.')
    if not s or s == '—':
        return None
    try:
        return float(s)
    except ValueError:
        return None


# ── Щитовидная железа: 8 заборов, у каждого «часов после приёма» ──────────
thyroid = []
p = TBL / 'Щитовидная железа.csv'
if p.exists():
    with p.open(encoding='utf-8') as f:
        rows = list(csv.DictReader(f))
    for r in rows:
        d = excel_date(r.get('Дата забора'))
        if d is None:          # первая строка — объединённая ячейка с референсами
            continue
        thyroid.append({
            'date': d,
            'lab': (r.get('Лаборатория / № отчёта') or '').strip(),
            'clinic': (r.get('Клиника') or '').strip(),
            't4_before': num(r.get('T4 до приёма (нмоль/л)')),
            't4_after': num(r.get('T4 после приёма (нмоль/л)')),
            'hours_after': (r.get('Часов после приёма') or '').strip(),
            'tsh': num(r.get('ТТГ (нг/мл)')),
            'weight': num(r.get('Вес (кг)')),
            'scheme': (r.get('Схема лечения на тот момент') or '').strip(),
            'verdict': (r.get('Вывод врача') or '').strip(),
        })

# ── Веса: из щитовидной + из рецептов (там вес на дату выписки) ───────────
weights = {}
for t in thyroid:
    if t['weight']:
        weights[t['date']] = t['weight']
p = TBL / 'Рецепты.csv'
if p.exists():
    with p.open(encoding='utf-8') as f:
        for r in csv.DictReader(f):
            d = excel_date(r.get('Дата'))
            w = num(r.get('Вес собаки (кг)'))
            if d and w:
                weights.setdefault(d, w)

# ── Рецепты -> эпизоды ────────────────────────────────────────────────────
prescriptions = []
if p.exists():
    with p.open(encoding='utf-8') as f:
        for r in csv.DictReader(f):
            d = excel_date(r.get('Дата'))
            if not d:
                continue
            prescriptions.append({
                'date': d,
                'no': (r.get('№ рецепта') or '').strip(),
                'clinic': (r.get('Клиника') or '').strip(),
                'vet': (r.get('Врач (+ № ордена)') or '').strip(),
                'drug': (r.get('Препарат') or '').strip(),
                'dose': (r.get('Дозировка') or '').strip(),
                'scheme': (r.get('Схема приёма') or '').strip(),
                'duration': (r.get('Длительность') or '').strip(),
            })

# ── Пробелы -> эпизоды (рабочий список для врача) ─────────────────────────
gaps = []
p = TBL / 'Пробелы.csv'
if p.exists():
    with p.open(encoding='utf-8') as f:
        for r in csv.DictReader(f):
            d = excel_date(r.get('Дата'))
            gaps.append({
                'date': d,
                'what': (r.get('Что отсутствует') or '').strip(),
                'why': (r.get('Почему это важно') or '').strip(),
                'todo': (r.get('Что сделать') or '').strip(),
            })

# ── Все анализы: 128 строк → 20 отчётов ───────────────────────────────────
#
# Группировка по (дата, раздел, № отчёта), а не по строке. Отчёт — это то,
# что человек держит в руках у врача; 128 отдельных записей в ленте
# нечитаемы, а двадцать отчётов с показателями внутри — это ровно то, что
# показывают на приёме.
reports = {}
p = TBL / 'Все анализы.csv'
if p.exists():
    with p.open(encoding='utf-8') as f:
        for r in csv.DictReader(f):
            d = excel_date(r.get('Дата'))
            if not d:
                continue
            key = (d, (r.get('Раздел') or '').strip(), (r.get('№ отчёта') or '').strip())
            reports.setdefault(key, {'lab': (r.get('Лаборатория') or '').strip(),
                                     'clinic': (r.get('Клиника') or '').strip(),
                                     'rows': []})
            reports[key]['rows'].append({
                'name': (r.get('Показатель') or '').strip(),
                'value': (r.get('Значение') or '').strip(),
                'unit': (r.get('Единицы') or '').strip(),
                'ref': (r.get('Референс') or '').strip(),
                'mark': (r.get('Отметка (↑ / ↓ / норма)') or '').strip(),
                'note': (r.get('Примечания') or '').strip(),
            })

# ── Все анализы: считаем, но в этот архив НЕ кладём ───────────────────────
#
# Замер 07.10.2026: строк данных 128, у всех 128 распознана дата, без даты 0.
# Записано числом, а не на память: `wc -l` минус заголовок отвечает на вопрос
# «сколько строк в файле», а нужен ответ «сколько записей». Разошлись на
# единицу именно поэтому.
ANALYSES_MEASURED = 128
analyses_count = 0
analyses_undated = 0
p = TBL / 'Все анализы.csv'
if p.exists():
    with p.open(encoding='utf-8') as f:
        for r in csv.DictReader(f):
            if excel_date(r.get('Дата')):
                analyses_count += 1
            else:
                analyses_undated += 1

# ── Сборка ────────────────────────────────────────────────────────────────
NOT_INCLUDED = [
    'структура: анализы лежат эпизодами, а не отдельной сущностью — модели «Исследование» нет',
    'диагнозы с датой и автором — нет модели «Диагноз»',
    'визиты к врачам — нет модели «Визит»',
    'схемы лечения с расчётом дозы на кг — нет полей `форма` и `доза на кг`',
    'УЗИ и гистопатология — нет модели «Визуальная диагностика»',
    'наблюдения владельца (13 записей) — нет модели',
    'указания по контролю с условиями забора — нет модели',
    'счета (29 строк) — нет модели',
]

episodes = []

# Предупреждение первым и с сегодняшней датой, чтобы оно было сверху.
episodes.append({
    'startedAt': iso(dt.date.today(), 9, 0),
    'title': 'НЕПОЛНЫЙ АРХИВ — приложение не сносить',
    'detail': ('Этот файл собран до того, как в приложении появились модели '
               'медицинского слоя. В нём есть: 20 отчётов анализов со 128 показателями, '
               'щитовидная железа, рецепты, веса и список пробелов — всё по-русски. '
               'В нём НЕТ:\n\n— ' + '\n— '.join(NOT_INCLUDED) +
               '\n\nИсточник: Google Doc «Медкнижка Стич, редакция 3 (свод на '
               '07.10.2026)» и таблица Stitch_analizy_i_recepty. Полный архив '
               'собирается после моделей.'),
})

for (date, section, number), rep in sorted(reports.items()):
    lines = []
    for row in rep['rows']:
        bit = row['name']
        # «нет данных» — это не значение, а его отсутствие. Печатать его
        # вместе с единицами («нет данных нмоль/L») значит делать вид,
        # что измерение было.
        пусто = row['value'].lower() in ('', '—', 'нет данных', 'не получен', 'н/д')
        if пусто:
            bit += ": результата нет"
        else:
            bit += f": {row['value']}"
            if row['unit'] and row['unit'] != '—':
                bit += f" {row['unit']}"
        if row['ref'] and row['ref'] not in ('—', 'не указана'):
            bit += f" (норма {row['ref']})"
        if row['mark'] and row['mark'] not in ('—', 'норма', 'нет данных'):
            bit += f"  ← {row['mark']}"
        lines.append(bit)
        if row['note']:
            lines.append(f"    {row['note']}")
    off = sum(1 for row in rep['rows']
              if row['mark'].startswith(('↑', '↓')) or row['mark'] == 'патология')
    # Номер отчёта — только если это правда номер. В таблице в этом поле
    # местами стоит проза («отчёт не получен»), и подставлять её после
    # «№» значит печатать бессмыслицу в заголовок.
    похож_на_номер = bool(number) and number != '—' and ' ' not in number
    head = f"Анализы — {section}" + (f", отчёт № {number}" if похож_на_номер else '')
    если_не_номер = '' if похож_на_номер or not number or number == '—' else f"\n\nОтчёт: {number}"
    detail = '\n'.join(lines)
    if rep['clinic'] or rep['lab']:
        detail += f"\n\n{rep['clinic']}"
        if rep['lab']:
            detail += f"\n{rep['lab']}"
    detail += если_не_номер
    detail += f"\n\nПоказателей {len(rep['rows'])}, вне нормы {off}."
    episodes.append({'startedAt': iso(date, 11, 0), 'title': head, 'detail': detail})

for t in thyroid:
    bits = []
    if t['t4_before'] is not None:
        bits.append(f"T4 до приёма {t['t4_before']} нмоль/л")
    if t['t4_after'] is not None:
        bits.append(f"T4 после приёма {t['t4_after']} нмоль/л")
    if t['hours_after'] and t['hours_after'] != '—':
        bits.append(f"через {t['hours_after']} ч после приёма")
    if t['tsh'] is not None:
        bits.append(f"ТТГ {t['tsh']} нг/мл")
    if t['weight'] is not None:
        bits.append(f"вес {t['weight']} кг")
    detail = '; '.join(bits)
    if t['scheme']:
        detail += f"\n\nСхема на тот момент: {t['scheme']}"
    if t['verdict']:
        detail += f"\n\nВывод врача: {t['verdict']}"
    if t['lab'] or t['clinic']:
        detail += f"\n\n{t['clinic']} · {t['lab']}"
    detail += ("\n\nРеференс T4 общий 12,9–51,5 нмоль/л. Терапевтический коридор "
               "для собак на заместительной терапии — 27–69 нмоль/л через 4–6 ч "
               "после приёма: это другая величина, не референс.")
    episodes.append({'startedAt': iso(t['date']), 'title': 'Щитовидная железа — забор', 'detail': detail})

for r in prescriptions:
    detail = f"{r['drug']}\n\nДоза: {r['dose']}\nСхема: {r['scheme']}\nДлительность: {r['duration']}"
    detail += f"\n\n{r['clinic']} · {r['vet']}"
    episodes.append({'startedAt': iso(r['date'], 10, 0),
                     'title': f"Рецепт № {r['no']}" if r['no'] else 'Рецепт',
                     'detail': detail})

for g in gaps:
    if not g['what']:
        continue
    episodes.append({'startedAt': iso(g['date'] or dt.date.today(), 8, 0),
                     'title': 'Пробел в документах',
                     'detail': f"{g['what']}\n\nПочему важно: {g['why']}\n\nЧто сделать: {g['todo']}"})

archive = {
    'formatVersion': 1,
    'createdAt': dt.datetime.now(dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'appVersion': 'НЕПОЛНЫЙ архив из медкнижки, собран 2026-10-07 — приложение не сносить',
    'dogs': [{
        'name': 'Stitch',
        'weightKg': 4.20,
        'foodBrand': '',
        'portionGrams': 0,
        'mealsPerDay': 2,
        'mealTimes': [],
        'forbiddenFoods': [],
        'rewards': [],
        'trainingFoodFromPortion': False,
        'markerKindRaw': 'clicker',
        'sessionLengthMinutes': 5,
        'isOnTreatment': True,
        'createdAt': '2023-03-19T00:00:00Z',
        'events': [],
        'weights': [{'date': iso(d), 'kg': kg} for d, kg in sorted(weights.items())],
        'careTasks': [{
            'title': 'Контроль Т4 и ТТГ',
            'detail': ('13.10.2026, 13:30, Vet Riviera. Утренняя доза в 09:30, '
                       'кормить как обычно, забор около 13:30 и не позже 15:30. '
                       'Время таблетки и время забора записать.'),
            'intervalDays': 42,
            'categoryRaw': 'vet',
            'snoozeCount': 0,
        }],
        'medications': [{
            'name': 'Euthyrox 75 мкг',
            'doseText': '1 таблетка',
            'times': [570, 1290],
            'fastingMinutes': 0,
            'isPaused': False,
            'doses': [],
        }],
        'trainingSteps': [],
        'trainingSessions': [],
        'trips': [],
    }],
    'members': [{'name': 'Виктория', 'roleRaw': 'owner', 'isMe': True, 'isOnDuty': True}],
    'episodes': episodes,
}

out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else 'стич-неполный.togo')
out.write_text(json.dumps(archive, ensure_ascii=False, indent=2), encoding='utf-8')

print(f"=== СОБРАНО ===")
print(f"файл          : {out}  ({out.stat().st_size} байт)")
print(f"весов         : {len(archive['dogs'][0]['weights'])}")
print(f"эпизодов      : {len(episodes)}")
print(f"  щитовидная  : {len(thyroid)}")
print(f"  рецепты     : {len(prescriptions)}")
print(f"  пробелы     : {len([g for g in gaps if g['what']])}")
print(f"  отчёты анализов: {len(reports)} ({analyses_count} показателей)")
print(f"  предупрежд. : 1")
print(f"лекарств      : {len(archive['dogs'][0]['medications'])}")
print(f"задач ухода   : {len(archive['dogs'][0]['careTasks'])}")
print()
print(f"НЕ ВОШЛО (перечислено и внутри файла):")
for n in NOT_INCLUDED:
    print(f"  — {n}")
print()
print(f"анализов в таблице: {analyses_count} с датой, {analyses_undated} без даты "
      f"(замер 07.10.2026 был {ANALYSES_MEASURED})")
if analyses_count != ANALYSES_MEASURED:
    print(f"  ВНИМАНИЕ: число изменилось против замера — таблицу пополнили, "
          f"пересними ЧЕГО-НЕ-ХВАТАЕТ-АРХИВУ.md")
