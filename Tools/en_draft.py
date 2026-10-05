#!/usr/bin/env python3
"""Английский черновик: накопить в файле, положить в каталог одним куском.

    python3 Tools/en_draft.py план          # что осталось перевести
    python3 Tools/en_draft.py партия 60     # следующие 60 ключей на перевод
    python3 Tools/en_draft.py проверить     # длины, подстановки, формы
    python3 Tools/en_draft.py положить      # перенести в каталог (целиком)

**Почему через отдельный файл, а не прямо в каталог.** Замерено подделкой
05.10.2026: один английский ключ в `Localizable.xcstrings` — и сторож
полноты даёт 2148 пробелов, код 65. Языки он берёт из каталога: язык,
встретившийся хоть у одного ключа, обязан быть у всех. Это сделано
намеренно (порог превратил бы сторожа в счётчик долга), и значит
**английский ложится в каталог целиком или не ложится вовсе.**

Черновик при этом копится в `docs/перевод/en-draft.json` и коммитится
по частям: незакоммиченное не существует, а 71 003 знака — не один вечер.

Проверки живут здесь, а не в чьей-то внимательности:

* **подстановки сходятся с ключом** по составу и порядку — `%lld`
  остаётся `%lld`, `%@` остаётся `%@`, литеральный процент остаётся `%%`;
* **формы числа** у ключа с `variations` обязаны быть и в английском
  (`one` и `other`), а у плоского — отсутствовать;
* **пусто — не перевод**: пустая строка проходит проверку
  на существование и не проходит проверку глазами;
* **помеченный пробел** (`"__ПРОБЕЛ__": причина`) законен и считается
  отдельно: молчаливый пробел неотличим от отсутствия работы,
  помеченный — лучше неверного обещания.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DRAFT = os.path.join(ROOT, "docs/перевод/en-draft.json")
CATALOGS = ["TogoShared/Resources/Localizable.xcstrings",
            "Togo/Resources/AppShortcuts.xcstrings"]
SPEC = re.compile(r"%(?:\d+\$)?(?:@|lld)")
GAP = "__ПРОБЕЛ__"

# Те же исключения, что у сторожа полноты: длинный список исключений —
# это сторож, который не может покраснеть.
PROPER = {"Lévothyrox", "Pro", "T+%@", "T0 / +4 / +6"}


def letters(key):
    return bool(re.search(r"[^\W\d_]", SPEC.sub("", key).replace("%%", ""), re.UNICODE))


def catalog():
    out = {}
    for name in CATALOGS:
        data = json.load(open(os.path.join(ROOT, name), encoding="utf-8"))
        for key, body in data["strings"].items():
            out[key] = (name, body)
    return out


def needed():
    """Ключи, которым нужен английский, в устойчивом порядке."""
    out = []
    for key, (_, body) in sorted(catalog().items()):
        if body.get("shouldTranslate") is False or not letters(key) or key in PROPER:
            continue
        out.append(key)
    return out


def shape(body):
    """Плоская строка или формы числа — по русскому/французскому узлу."""
    for language in ("fr", "uk", "ru"):
        node = body.get("localizations", {}).get(language)
        if node and "variations" in node:
            return sorted(node["variations"]["plural"].keys())
    return None


def draft():
    if not os.path.exists(DRAFT):
        return {}
    return json.load(open(DRAFT, encoding="utf-8"))


def save(data):
    os.makedirs(os.path.dirname(DRAFT), exist_ok=True)
    with open(DRAFT, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=1, sort_keys=True)
        handle.write("\n")


def specs(text):
    return SPEC.findall(text)


def problems(key, value, body):
    out = []
    forms = shape(body)
    if isinstance(value, dict) and GAP in value:
        if not str(value[GAP]).strip():
            out.append("помеченный пробел без причины")
        return out
    if isinstance(value, dict):
        if not forms:
            out.append("формы числа у плоского ключа")
            return out
        missing = {"one", "other"} - set(value)
        if missing:
            out.append(f"нет английских форм: {sorted(missing)}")
        for form, text in value.items():
            out += [f"[{form}] {item}" for item in flat_problems(key, text)]
        return out
    if forms:
        out.append(f"ключ с формами числа, а перевод плоский (нужны one/other; "
                   f"в источнике {forms})")
    out += flat_problems(key, value)
    return out


def flat_problems(key, text):
    out = []
    if not isinstance(text, str) or not text.strip():
        out.append("пусто — это не перевод")
        return out
    want, got = specs(key), specs(text)
    if [x.replace("1$", "").replace("2$", "").replace("3$", "").replace("4$", "") for x in want] != \
       [x.replace("1$", "").replace("2$", "").replace("3$", "").replace("4$", "") for x in got]:
        out.append(f"подстановки разошлись: в ключе {want}, в переводе {got}")
    if key.count("%%") != text.count("%%"):
        out.append(f"литеральный процент: в ключе {key.count('%%')}, "
                   f"в переводе {text.count('%%')} — нужен %%, не %")
    return out


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "план"
    have, cat, keys = draft(), catalog(), needed()
    todo = [k for k in keys if k not in have]

    if command == "план":
        done = len(keys) - len(todo)
        gaps = sum(1 for v in have.values() if isinstance(v, dict) and GAP in v)
        chars = sum(len(k) for k in todo)
        print(f"ключей под английский   {len(keys)}")
        print(f"  переведено            {done}")
        print(f"  помеченных пробелов   {gaps}")
        print(f"  осталось              {len(todo)}  ({chars} знаков русского)")
        return 0

    if command == "партия":
        size = int(sys.argv[2]) if len(sys.argv) > 2 else 60
        batch = []
        for key in todo[:size]:
            _, body = cat[key]
            item = {"ru": key}
            forms = shape(body)
            if forms:
                item["формы"] = forms
                node = (body["localizations"].get("fr")
                        or body["localizations"].get("uk"))
                item["fr"] = {f: node["variations"]["plural"][f]["stringUnit"]["value"]
                              for f in node["variations"]["plural"]}
            else:
                # Французский как опора: он вычитан лучше украинского
                # и показывает принятые термины. Украинский в партию
                # не печатается — он удваивал бы чтение, не добавляя
                # решений.
                node = body.get("localizations", {}).get("fr")
                if node and "stringUnit" in node:
                    item["fr"] = node["stringUnit"]["value"]
            batch.append(item)
        print(json.dumps(batch, ensure_ascii=False, indent=1))
        return 0

    if command == "проверить":
        bad, gaps = [], 0
        for key, value in sorted(have.items()):
            if key not in cat:
                bad.append(f"{key[:60]}: ключа нет в каталоге — черновик протух")
                continue
            if isinstance(value, dict) and GAP in value:
                gaps += 1
            for item in problems(key, value, cat[key][1]):
                bad.append(f"{key[:60]}: {item}")
        print(f"в черновике {len(have)} записей, помеченных пробелов {gaps}")
        if bad:
            print(f"✘ находок {len(bad)}")
            for item in bad[:40]:
                print("  •", item)
            return 1
        print("✔ подстановки, формы и пустоты в порядке")
        print(f"\nОсталось непереведённых: {len(todo)}. "
              f"Пока их больше нуля, в каталог класть нельзя: "
              f"сторож полноты требует язык у ВСЕХ ключей.")
        return 0

    if command == "положить":
        if todo:
            print(f"нельзя: непереведённых {len(todo)}. Английский ложится целиком — "
                  f"замерено подделкой, один ключ даёт 2148 пробелов.")
            return 1
        return put(have, cat)

    print(__doc__)
    return 1


def put(have, cat):
    import unicodedata  # noqa: F401  (на случай будущей нормализации)
    written = 0
    for name in CATALOGS:
        path = os.path.join(ROOT, name)
        data = json.load(open(path, encoding="utf-8"))
        for key, body in data["strings"].items():
            if key not in have:
                continue
            value = have[key]
            if isinstance(value, dict) and GAP in value:
                continue  # помеченный пробел кладётся НЕ переводом, а записью в журнал
            node = body.setdefault("localizations", {})
            if isinstance(value, dict):
                node["en"] = {"variations": {"plural": {
                    form: {"stringUnit": {"state": "needs_review", "value": text}}
                    for form, text in value.items()}}}
            else:
                node["en"] = {"stringUnit": {"state": "needs_review", "value": value}}
            body["localizations"] = {k: node[k] for k in sorted(node)}
            written += 1
        text = json.dumps(data, ensure_ascii=False, indent=2, separators=(",", " : "))
        text = re.sub(r'(\n( *)"(?:[^"\\]|\\.)*" : )\{\}',
                      lambda m: m.group(1) + "{\n\n" + m.group(2) + "}", text)
        open(path, "w", encoding="utf-8").write(text)
    print(f"положено английских записей: {written}")
    print("дальше: make unit — и поднять долг `en` в LocalizationCoverageTests")
    return 0


if __name__ == "__main__":
    sys.exit(main())
