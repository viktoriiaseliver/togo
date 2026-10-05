#!/usr/bin/env python3
"""Побуквенная сверка витрины в App Store Connect с fastlane/metadata.

    source ../Gamut/.env.asc
    python3 Tools/check_storefront_text.py              # все локали
    python3 Tools/check_storefront_text.py fr-FR uk     # выбранные

Код возврата 0 — всё сошлось, 1 — есть расхождение, 2 — не прочитать ASC.
Ничего не пишет: записью занимается `asc_storefront_locale.py --write`.

**Почему отдельной командой, а не режимом внутри того скрипта.**
Он пишет в витрину, этот проверяет витрину. Инструмент, который пишет,
и инструмент, который проверяет, не должны делить код: иначе проверяем
одну реализацию ею же. Авторизация и запросы всё-таки берутся импортом —
вторая реализация одного правила расходится с первой молча, и 05.10
у Gamut это стоило сорока одной ложной строки в наряде переводчику.

## Три урока 05.10.2026, каждый оплачен, каждый вшит сюда

**1. Длина — не текст.** Первая сверка этой витрины сравнивала ДЛИНЫ
и доложила «расхождений нет». Побуквенная нашла четыре пустых поля,
среди них ссылку на политику приватности у французской и украинской
карточки. Длина — хеш с одним байтом энтропии на поле; формулировка
сессии Gamut. Текст у ASC есть, значит сравнивать надо текст.

> Границу тогда назвали верно — «сильное свидетельство, а не
> доказательство» — и на этом остановились. **Названная граница
> не снимает её; снимает только работа.**

**2. Поля живут на ДВУХ ручках, и запрос не на ту ручку врёт целиком.**

    privacyPolicyUrl, name, subtitle  →  appInfoLocalizations
    supportUrl, description, …        →  appStoreVersionLocalizations

Менеджер послал оба поля одним телом на ручку версии и получил `409`
на всех четырёх локалях, включая целые. Негодное поле отравило весь
запрос, и ответ секунду читался как «пусто у всех четырёх».

**3. Отсутствие поля в ответе и пустое поле — разные вещи**, и обе
печатаются здесь по-разному. Первая сверка напечатала «fr-FR — 5 полей»
при семи у `ru`, разницу увидели и не спросили, откуда она:
**отсутствие прочиталось как меньший объём, а не как дыра.**

## И то, из-за чего печатаются идентификаторы и время

05.10 два замера одного поля разошлись, и рассудить их оказалось
нечем: состояние, которое их разделяло, к тому времени переписали.
Отчёт без состояния — утверждение о витрине, которой больше нет.
Поэтому первыми строками идут идентификаторы записей, их состояние
и время замера.
"""
import hashlib
import importlib.util
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Авторизация, `call` и списки полей — у того же скрипта, что пишет.
_spec = importlib.util.spec_from_file_location(
    "asc_storefront_locale", os.path.join(ROOT, "Tools", "asc_storefront_locale.py"))
_asc = importlib.util.module_from_spec(_spec)
_saved_argv, sys.argv = sys.argv, ["asc_storefront_locale"]
_spec.loader.exec_module(_asc)
sys.argv = _saved_argv

# Какое поле на какой ручке. Таблица здесь, а не в голове: ошибка
# в ней даёт «пусто» там, где всё цело.
HANDLES = [
    ("appInfoLocalizations", "appInfos", _asc.INFO_FIELDS),
    ("appStoreVersionLocalizations", "appStoreVersions", _asc.VERSION_FIELDS),
]

ОТСУТСТВУЕТ = object()


def sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:12]


def живое(parent_type, parent_id, handle):
    """Все локали одной ручки: {locale: {поле: значение | ОТСУТСТВУЕТ}}."""
    status, data = _asc.call(f"{parent_type}/{parent_id}/{handle}")
    if data is None:
        sys.exit(f"не прочитать {handle}: HTTP {status}")
    out = {}
    for item in data["data"]:
        attrs = item["attributes"]
        out[attrs["locale"]] = attrs
    return out


def из_файла(locale, name):
    path = os.path.join(ROOT, "fastlane", "metadata", locale, name)
    if not os.path.exists(path):
        return None
    return open(path, encoding="utf-8").read().strip()


def main():
    выбранные = [a for a in sys.argv[1:] if not a.startswith("-")]

    status, infos = _asc.call(f"apps/{_asc.APP_ID}/appInfos")
    if infos is None:
        sys.exit(2)
    info = infos["data"][0]
    status, versions = _asc.call(f"apps/{_asc.APP_ID}/appStoreVersions?limit=1")
    if versions is None:
        sys.exit(2)
    version = versions["data"][0]

    # Состояние замера — первыми строками. Без него отчёт говорит
    # о витрине, которой через час может не быть.
    print(f"замер {time.strftime('%d.%m.%Y %H:%M:%S %z')}")
    print(f"приложение {_asc.APP_ID}")
    print(f"  appInfo          {info['id']}  {info['attributes']['state']}")
    print(f"  версия {version['attributes']['versionString']:8} {version['id']}  "
          f"{version['attributes']['appStoreState']}")

    родители = {"appInfos": info["id"], "appStoreVersions": version["id"]}
    состояние = {handle: живое(parent, родители[parent], handle)
                 for handle, parent, _ in HANDLES}

    локали = sorted({l for h in состояние.values() for l in h})
    if выбранные:
        неизвестные = [l for l in выбранные if l not in локали]
        if неизвестные:
            # Код 2, а не 1: сверка НЕ ПРОШЛА, а не «нашла расхождение».
            # Один код на оба исхода прочтут как находку — и пойдут
            # чинить витрину там, где опечатка в аргументе.
            print(f"нет в витрине: {', '.join(неизвестные)}; "
                  f"есть {', '.join(локали)}", file=sys.stderr)
            sys.exit(2)
        локали = выбранные

    сверено = разошлось = нет_файла = нет_локали = 0

    for locale in локали:
        print(f"\n=== {locale}")
        for handle, _, fields in HANDLES:
            если_нет = состояние[handle].get(locale)
            if если_нет is None:
                нет_локали += 1
                print(f"  {handle}: ЛОКАЛИ НЕТ — поля этой ручки не сверялись")
                continue
            for key, (name, limit) in fields.items():
                файл = из_файла(locale, name)
                if файл is None:
                    нет_файла += 1
                    print(f"  {key:17} файла fastlane/metadata/{locale}/{name} нет")
                    continue
                # Отсутствие поля в ответе и пустое поле — разные вещи.
                if key not in если_нет:
                    значение, вид = ОТСУТСТВУЕТ, "ПОЛЯ НЕТ В ОТВЕТЕ"
                else:
                    значение = если_нет[key] or ""
                    вид = "ПУСТО" if значение == "" else None

                сверено += 1
                if значение is not ОТСУТСТВУЕТ and значение == файл:
                    print(f"  {key:17} СОВПАЛ   sha {sha(файл)}  {len(файл)} знаков")
                    continue

                разошлось += 1
                if вид:
                    print(f"  {key:17} РАСХОЖДЕНИЕ: в ASC {вид}, "
                          f"в файле {len(файл)} знаков  sha {sha(файл)}")
                    continue
                i = next((i for i, (a, b) in enumerate(zip(файл, значение)) if a != b),
                         min(len(файл), len(значение)))
                print(f"  {key:17} РАСХОЖДЕНИЕ: файл sha {sha(файл)} ({len(файл)}) "
                      f"≠ ASC sha {sha(значение)} ({len(значение)})")
                print(f"  {'':17} первый расходящийся знак {i}:")
                print(f"  {'':17}   файл {файл[i:i + 50]!r}")
                print(f"  {'':17}   ASC  {значение[i:i + 50]!r}")

    print(f"\nсверено побуквенно: {сверено} полей, расхождений {разошлось}")
    if нет_файла:
        print(f"файла в fastlane/metadata не было: {нет_файла} — это НЕ «совпало»")
    if нет_локали:
        print(f"локаль отсутствует на ручке: {нет_локали} раз — поля не сверялись вовсе")

    # Границы печатаются всегда и называют, что их снимет: граница,
    # не называющая этого, переживает свою причину молча.
    print("\nчего эта сверка НЕ проверяет:")
    print("  · поля вне INFO_FIELDS и VERSION_FIELDS — их список берётся"
          " у asc_storefront_locale.py;")
    print("    снимет границу: дописать поле туда, сверка подхватит сама;")
    print("  · что витрина вообще обещает эти локали — это"
          " Tools/check_storefront_languages.py;")
    print("  · кадры витрины: их тут нет ни одного, и текст о них ничего не знает.")

    sys.exit(1 if разошлось else 0)


if __name__ == "__main__":
    main()
