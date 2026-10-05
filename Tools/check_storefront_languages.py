#!/usr/bin/env python3
"""Ворота перед отправкой: витрина обещает только то, что умеет бандл.

    python3 Tools/check_storefront_languages.py [путь/к/Togo.app]

По умолчанию берётся `build/Togo.xcarchive/Products/Applications/Togo.app` —
бандл **того архива, который собираются заливать**, а не любой сборки.
Отпечаток печатается рядом: «та ли сборка» должно быть вопросом с ответом,
а не мнением.

Проверяет две вещи, и обе — про расхождение между тем, чем заняты
разные люди.

**1. Язык метаданных без языка в бандле.** У витрины два разных списка:
локали описаний (их задаёт `appStoreVersionLocalizations`) и языки
приложения — их Apple берёт **из бинарника**. Первый растёт росчерком
в API, второй — только переводом. 05.10.2026 локаль `en-US` заведена
при нуле английских строк в приложении, и поймать это было нечем:
сторожа не существовало.

**2. Цитату интерфейса в описании витрины.** Английское описание зовёт
кнопки по именам («NEEDS TO GO OUT?»), и эти имена обязаны совпасть
со строками приложения дословно, иначе человек пойдёт искать и не найдёт.
Внутри каталога такие места охраняет `QuotedNamesTests` — 56 цитат;
между каталогом и витриной не охраняло ничто.

Почему скриптом, а не тестом: тест читает каталог, а каталог — это то,
что мы думаем. Бандл — то, что получилось.
"""
import glob
import json
import os
import plistlib
import re
import subprocess
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_APP = os.path.join(ROOT, "build/Togo.xcarchive/Products/Applications/Togo.app")

# Цитата витрины ↔ ключ каталога. Ключ — он же русская строка.
#
# Требование формулируется про ТЕКСТ КЛЮЧА, а не про регистр в описании:
# «Просится» цитируется дважды — прописными в заголовке раздела
# и строчными в тексте, — а ключ один. Сверка без этой оговорки дала бы
# ложное расхождение, а ложное расхождение дороже пропущенного дефекта:
# после девятого сторожа перестают читать.
QUOTE_PAIRS = {
    "Просится": "Needs to go out?",
    "Непонятно": "not sure",
    "Вывожу": "Taking her out",
    "как попросил": "how she asked",
    "не брал еду": "didn't take food",
}

# Седьмая цитата убрана из описания 05.10.2026 НАМЕРЕННО: точного ключа
# под «dose → blood draw» нет, строка живёт внутри длинной фразы. Названа
# здесь, чтобы следующий не завёл под неё ключ ради витрины.
REMOVED_QUOTE = "dose → blood draw"


def norm(text):
    """Невидимое к видимому: узкий неразрывный пробел — это пробел.

    У французского «Просится» стоит U+202F перед `?` — правильная
    типографика, из-за которой побайтная сверка покраснела бы на верном
    переводе.
    """
    text = unicodedata.normalize("NFC", text)
    for space in (" ", " ", " "):
        text = text.replace(space, " ")
    return text.strip()


def bundle_languages(app):
    """Языки бандла — папки `.lproj`, в которых есть `Localizable.strings`.

    **Не всякая `.lproj` — язык.** Замер 05.10.2026: `en.lproj` с единственным
    файлом `nlu.appintents` появился в одной сборке из четырёх одного кода
    (его порождает Xcode для английского сам, причина не установлена).
    Считать его языком значит остановить выгрузку из-за служебного
    артефакта, то есть научить не верить красному.
    """
    real, service = {}, {}
    for path in sorted(glob.glob(os.path.join(app, "*.lproj"))):
        code = os.path.basename(path)[:-len(".lproj")]
        if code == "Base":
            continue
        strings = os.path.join(path, "Localizable.strings")
        if os.path.exists(strings):
            real[code] = strings
        else:
            service[code] = sorted(os.listdir(path))
    return real, service


def read_strings(path):
    with open(path, "rb") as handle:
        head = handle.read(8)
    if head.startswith(b"bplist"):
        with open(path, "rb") as handle:
            return plistlib.load(handle)
    # Текстовый .strings бывает у несобранных ресурсов — через plutil,
    # чтобы не писать свой разбор формата.
    out = subprocess.run(["plutil", "-convert", "json", "-o", "-", path],
                         capture_output=True)
    return json.loads(out.stdout) if out.returncode == 0 else {}


def metadata_locales():
    out = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "fastlane/metadata/*"))):
        if not os.path.isdir(path) or not os.path.exists(
                os.path.join(path, "description.txt")):
            continue
        locale = os.path.basename(path)
        out[locale] = locale.split("-")[0]
    return out


def main():
    app = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_APP
    if not os.path.isdir(app):
        sys.exit(f"нет бандла: {app}\n"
                 f"собери архив (`make archive`) или укажи путь первым аргументом")

    fingerprint = subprocess.run(
        ["shasum", "-a", "256", os.path.join(app, os.path.basename(app)[:-4])],
        capture_output=True, text=True).stdout.split()
    print(f"бандл      {app}")
    if fingerprint:
        print(f"отпечаток  {fingerprint[0][:16]}…  (бинарник)")

    real, service = bundle_languages(app)
    print(f"языки      {sorted(real)}")
    for code, files in service.items():
        print(f"  служебная {code}.lproj без Localizable.strings: {files} — не язык")

    locales = metadata_locales()
    print(f"локали витрины в fastlane/metadata: {sorted(locales)}")

    problems = []

    for locale, language in sorted(locales.items()):
        if language not in real:
            problems.append(
                f"локаль витрины «{locale}» обещает язык «{language}», "
                f"которого в бандле нет.\n"
                f"    Описание на этом языке человек прочтёт, а приложение "
                f"откроется на языке разработки.")

    # Цитаты: сверяем с бандлом, а не с каталогом.
    description = os.path.join(ROOT, "fastlane/metadata/en-US/description.txt")
    if os.path.exists(description) and "en" in real:
        text = open(description, encoding="utf-8").read()
        english = read_strings(real["en"])
        for key, expected in sorted(QUOTE_PAIRS.items()):
            if norm(expected).lower() not in norm(text).lower():
                problems.append(
                    f"цитата «{expected}» из пары для ключа «{key}» "
                    f"в описании больше не стоит — пара протухла, убери её.")
                continue
            actual = english.get(key)
            if actual is None:
                problems.append(
                    f"ключ «{key}» не переведён на английский, а витрина "
                    f"цитирует его как «{expected}».")
            elif norm(actual).lower() != norm(expected).lower():
                problems.append(
                    f"витрина зовёт «{expected}», приложение говорит "
                    f"«{actual}» (ключ «{key}»).\n"
                    f"    Человек пойдёт искать и не найдёт.")
        if REMOVED_QUOTE in text and f"“{REMOVED_QUOTE}”" in text:
            problems.append(
                f"«{REMOVED_QUOTE}» снова в кавычках в описании. Точного "
                f"ключа под эту строку нет: она живёт внутри длинной фразы. "
                f"Либо убрать кавычки, либо завести ключ — и тогда дописать "
                f"пару сюда.")
    elif os.path.exists(description):
        print("  цитаты не сверялись: английского в бандле нет "
              "(и это уже названо выше проблемой)")

    print()
    if problems:
        print(f"✘ находок: {len(problems)}")
        for item in problems:
            print(f"  • {item}")
    else:
        print("✔ витрина не обещает языка, которого нет, и цитирует "
              "приложение дословно")

    # Границы собственного умения — последней строкой, а не в чьей-то памяти.
    print("""
Что эти ворота НЕ проверяют:
  · полноту перевода — язык в бандле может быть почти пустым (сторож
    полноты каталога — `LocalizationCoverageTests`);
  · локали, заведённые в App Store Connect и не лежащие в
    `fastlane/metadata` — витрина живёт вне git, сверять её состояние
    отдельно: `Tools/asc_storefront_locale.py <локаль>`;
  · остальной текст описания: сверяются только цитаты из списка выше,
    пять ключей и шесть вхождений;
  · седьмая цитата «dose → blood draw» снята с кавычек намеренно —
    ключа под неё нет и заводить его ради витрины не надо.
Узкий неразрывный пробел, неразрывный и тонкий приравнены к обычному:
иначе правильная французская типографика читалась бы расхождением.""")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
