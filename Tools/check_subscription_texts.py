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
        if missing:
            problems.append(
                f"{product}: витрина заявляет локали {missing}, а у продукта их нет.\n"
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
