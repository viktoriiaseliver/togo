#!/usr/bin/env python3
"""Тексты подписок против пределов Apple и против локалей витрины.

    python3 Tools/check_subscription_texts.py

Два предела и одна полнота:

* имя продукта ≤ 30 знаков, описание ≤ 45. **Предел режет, а не
  переносит** — строка 46 знаков не укоротится сама, она обрежется
  у человека на листе оплаты. У Gamut русские описания были 53, 74 и 86
  знаков, то есть не влезали никогда; у Timer английское 61 и не влезает
  прямо сейчас. Поэтому проверка скриптом, а не глазом;
* локали продукта обязаны **покрывать** локали витрины. Замер 05.10.2026
  на Togo: витрина заявляет `ru fr-FR uk en-US`, у обеих подписок была
  одна `ru`. Француз, украинец и англичанин видели русское название там,
  где отдают деньги. В отчётах этого не было ни у кого: два списка живут
  в разных ручках API, и сравнить их было некому.

Что этот скрипт НЕ проверяет — напечатано последней строкой.
"""
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAN = os.path.join(ROOT, "fastlane/metadata/ru/subscriptions.json")
LIMITS = {"name": 30, "description": 45}
# Локаль плана — русская; в витрине она же называется `ru`.
BASE_LOCALE = "ru"

# Локали, которых у продукта НЕ БУДЕТ, и это не долг, а отказ Apple.
#
# 03.11.2026: этот скрипт падал на `kk` каждый прогон — и за привычным
# красным спряталась настоящая находка. Восемь описаний подписок обещали
# «матрицу переноса навыка», убранную из Pro 24.10, и скрипт их видел.
# Его вывод не читали, потому что rc=1 у него был нормой.
#
# > **Прогон с привычным красным перестают читать целиком.** Прятать
# > из вывода можно то, что уже объяснено, — поэтому `kk` печатается
# > по-прежнему, но находкой не считается.
#
# Чем объяснён: замер 23.10.2026, коммит `abde131b`. Apple отвергает
# локаль `kk` ДВУМЯ разными эндпоинтами с разным текстом отказа —
# 409 «'kk' is not a valid locale» у appInfoLocalizations и 409 «The
# language specified is not listed for localization» у
# appStoreVersionLocalizations, — при контроле en-US/fr-FR/uk той же
# минутой тем же ключом: 201/200. То есть отказ про язык, а не про ключ.
#
# Что сделает эту запись ложной: Apple заведёт `kk` в список локалей
# витрины. Проверяется заливкой казахских текстов, они лежат готовыми
# в `fastlane/metadata/kk/`.
ОТКАЗАНО_APPLE = {"kk"}
ОТКАЗАНО_APPLE_ПОЧЕМУ = (
    "Apple не принимает её для витрины (замер 23.10.2026, abde131b, "
    "два эндпоинта, два разных 409 при живом контроле на трёх локалях)")


def storefront_locales():
    """Локали витрины — по папкам метаданных, а не по памяти."""
    out = set()
    for path in sorted(glob.glob(os.path.join(ROOT, "fastlane/metadata/*"))):
        if os.path.isdir(path) and os.path.exists(os.path.join(path, "description.txt")):
            out.add(os.path.basename(path))
    return out


def main():
    plan = json.load(open(PLAN, encoding="utf-8"))
    wanted = storefront_locales()
    problems = []

    print(f"локали витрины: {sorted(wanted)}")
    for product, body in sorted(plan["products"].items()):
        have = {BASE_LOCALE: {"name": body["name"], "description": body["description"]}}
        have.update(body.get("localizations", {}))
        print(f"\n{product}  цена {body['price']}")
        for locale in sorted(have):
            texts = have[locale]
            marks = []
            for field, limit in LIMITS.items():
                value = texts.get(field)
                if value is None:
                    problems.append(f"{product} · {locale}: нет поля «{field}»")
                    marks.append(f"{field} —")
                    continue
                size = len(value)
                marks.append(f"{field} {size}/{limit}")
                if size > limit:
                    problems.append(
                        f"{product} · {locale}: «{field}» {size} знаков при пределе "
                        f"{limit}. Обрежется у человека, а не перенесётся.")
            print(f"  {locale:6} {' · '.join(marks)}")
            print(f"         «{texts.get('name')}» / «{texts.get('description')}»")

        missing = sorted(wanted - set(have))
        объяснённые = sorted(set(missing) & ОТКАЗАНО_APPLE)
        настоящие = sorted(set(missing) - ОТКАЗАНО_APPLE)
        if объяснённые:
            print(f"  ⚠ локали {объяснённые} у продукта нет, и не будет: "
                  f"{ОТКАЗАНО_APPLE_ПОЧЕМУ}")
        if настоящие:
            problems.append(
                f"{product}: витрина заявляет локали {настоящие}, а у продукта их нет.\n"
                f"    На листе оплаты человек прочтёт название на языке разработки.")

    print()
    if problems:
        print(f"✘ находок: {len(problems)}")
        for item in problems:
            print(f"  • {item}")
    else:
        print("✔ пределы соблюдены, локали продуктов покрывают витрину")

    print("""
Что НЕ проверяется здесь:
  · состояние в App Store Connect — этот файл говорит, чего мы хотим,
    а не что залито. Сверять ручкой:
    GET /v1/subscriptions/{id}/subscriptionLocalizations;
  · `Configuration/Togo.storekit` — у него свои тексты и ПРЕДЕЛОВ НЕТ.
    Замер 05.10.2026: там лежит описание на 78 знаков, которое в витрину
    не влезет никогда. Значит песочница показывает не то, что магазин,
    и кадры с неё — не кадры витрины;
  · смысл перевода: длина сошлась — не значит, что фраза читается.
    «2e chien» вместо «deuxième chien» влезло в предел, но это сокращение,
    и носитель должен сказать, годится ли оно на экране оплаты.""")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
