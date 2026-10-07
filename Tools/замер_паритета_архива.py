#!/usr/bin/env python3
"""Замер разрыва «модель → снимок архива»: какие хранимые поля НЕ едут в бэкап.

Это ЗАМЕР, а не правка: скрипт ничего не пишет, кроме своего вывода.

Чего он НЕ умеет — печатается последней строкой вывода, а не живёт
в чьей-то памяти.

Почему разбор по скобкам, а не регуляркой: членом класса считается только
то, что стоит на уровне тела. Разбор по одной строке не отличает поле
от локальной переменной внутри вычисляемого свойства и ошибается
в сторону полноты — то есть в сторону, которая выглядит безопаснее
и не является. Так уже был испорчен снимок схемы V3 (`~/Projects/CLAUDE.md`).

Состояние, по которому мерим, задаётся ключом --ref: рабочее дерево
(`--ref worktree`) или коммит (`--ref HEAD`). Отчёт без состояния — это
утверждение о файле, которого больше нет.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

ARCHIVE_PATH = "TogoShared/Domain/BackupArchive.swift"
MODEL_GLOB = "TogoShared/Models/*.swift"

# Соответствие модель → структура снимка выводится ИЗ ИСХОДНИКА:
# `Dog` → `DogSnapshot`. Руками перечислены только те, где имена
# не совпадают, и список исключений закрыт.
#
# **Первая редакция держала руками ВСЮ таблицу, и это был дефект
# ровно того класса, за который мы ругаем сторожей.** `togo-05` завёл
# `ProcedureSkillSnapshot`, а инструмент сказал «снимка нет вовсе» —
# то есть измеритель полноты выдал СВОЮ неполноту за находку о мире.
# Нашёл это не я и не мой порог: нашёл человек, который правил код
# и спросил инструмент после правки.
#
# > Инструмент с перечнем руками знает только то, что в него положили.
SNAPSHOT_RENAMED = {
    "LogEvent": "EventSnapshot",
    "WeightEntry": "WeightSnapshot",
    "DoseRecord": "DoseSnapshot",
    "FoodStock": "StockSnapshot",
    "HeatRecord": "HeatSnapshot",
    "DogDocument": "DocumentSnapshot",
    "FamilyMember": "MemberSnapshot",
}

# Реестр решений «поле живёт только на этом телефоне» — читается
# из сторожа `DeviceLocalFieldTests`, а не повторяется здесь копией.
# Без него каждое новое device-local поле выглядит дырой в архиве,
# и перечень перестают читать.
DEVICE_LOCAL_SOURCE = "TogoTests/DeviceLocalFieldTests.swift"

# Реестр решений «в снимке нет НАМЕРЕННО» — тоже читается из сторожа,
# а не копируется. Заведено 07.10.2026 после того, как собственное
# решение («`awaitedMedicationID` не везём: восстановленная ссылка
# указывала бы в никуда») этот инструмент назвал потерей — то есть
# выдал за находку то, что решено минутой раньше.
#
# > Копия реестра расходится с реестром молча, а инструмент при этом
# > докладывает уверенно.
INTENTIONAL_SOURCE = "TogoTests/ArchiveParityTests.swift"

# Классы полей, которые «не едут» по устройству формата, а не по
# недосмотру. Их держат ОТДЕЛЬНО от настоящих потерь: пятнадцать
# одинаковых «не едет id» хоронят одну настоящую находку, а после
# девяти ложных сторожей перестают читать.
#
# `id`         — тождество записи. Архив его не несёт нигде, кроме
#                `EventSnapshot`: при восстановлении записи заводятся
#                заново. Это решение формата, и оно одно, а не
#                пятнадцать находок.
# `changedAt`  — метка слияния («позже побеждает» в `SharedDiaryMerge`).
#                Относится к обмену между телефонами, а не к тому, что
#                человек ввёл.
SERVICE_FIELDS = {"id", "changedAt"}

# Сколько @Model ожидается в дереве. Порог «было что мерить»: разбор,
# нашедший меньше, ослеп — и обязан сказать это, а не назвать список.
EXPECTED_MODEL_COUNT = 16
MIN_FIELDS_PER_MODEL = 2
# Сколько снимков ожидается в архиве и сколько моделей НАИБОЛЬШЕЕ может
# остаться без снимка, прежде чем верить надо разбору, а не миру.
# Порог заведён после подделки: разбор, не нашедший ни одной структуры,
# сказал бы «снимка нет вовсе» про все шестнадцать моделей — то есть
# выдал бы круглое число за находку. «Всё сошлось» и «ничего
# не сошлось» подозрительны одинаково.
MIN_SNAPSHOT_STRUCTS = 10
MAX_MODELS_WITHOUT_SNAPSHOT = 3

DECL = re.compile(
    r"""^\s*
    (?P<attrs>(?:@\w+(?:\([^)]*\)|\s*\([^)]*\))?\s*)*)   # @Attribute(...), @Relationship(...)
    (?P<mods>(?:(?:private|fileprivate|internal|public|final|nonisolated|weak|unowned|lazy)
               (?:\(set\))?\s+)*)
    (?P<kind>var|let)\s+
    (?P<name>\w+)\s*
    (?::\s*(?P<type>[^={]+?))?\s*
    (?P<tail>=.*|\{.*)?$
    """,
    re.VERBOSE,
)


def strip_noise(line: str) -> str:
    """Убрать строковые литералы и комментарий, чтобы скобки в них
    не сдвигали глубину. Интерполяция внутри литерала уезжает вместе
    с ним — она нам не нужна, а её скобки портили бы счёт."""
    out, i, in_str = [], 0, False
    while i < len(line):
        ch = line[i]
        if in_str:
            if ch == "\\" and i + 1 < len(line):
                i += 2
                continue
            if ch == '"':
                in_str = False
            i += 1
            continue
        if ch == '"':
            in_str = True
            i += 1
            continue
        if ch == "/" and i + 1 < len(line) and line[i + 1] == "/":
            break
        out.append(ch)
        i += 1
    return "".join(out)


def read(ref: str, path: str) -> str:
    if ref == "worktree":
        return (ROOT / path).read_text(encoding="utf-8")
    return subprocess.run(
        ["git", "--no-optional-locks", "show", f"{ref}:{path}"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout


def list_files(ref: str, glob: str) -> list[str]:
    if ref == "worktree":
        return sorted(str(p.relative_to(ROOT)) for p in ROOT.glob(glob))
    out = subprocess.run(
        ["git", "--no-optional-locks", "ls-tree", "-r", "--name-only", ref,
         str(Path(glob).parent)],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout.split()
    return sorted(p for p in out if p.endswith(".swift"))


def body_at(lines: list[str], start: int) -> list[str]:
    """Тело объявления, начинающегося на строке `start`, по скобкам.

    Возвращает строки УРОВНЯ ТЕЛА (глубина 1). Всё, что глубже,
    отброшено: там живут локальные переменные вычисляемых свойств
    и поля вложенных структур.
    """
    depth = 0
    own: list[str] = []
    started = False
    for i in range(start, len(lines)):
        clean = strip_noise(lines[i])
        before = depth
        opened = clean.count("{")
        closed = clean.count("}")
        if before == 1:
            # Строка уровня тела. Если она открывает свой блок
            # (вычисляемое свойство, функция, вложенная структура) —
            # сама строка телу принадлежит, её внутренности нет.
            own.append(lines[i])
        depth += opened - closed
        if opened:
            started = True
        if started and depth <= 0:
            break
    return own


def bodies(text: str, opener: re.Pattern[str]) -> dict[str, list[str]]:
    """Все объявления, отобранные по `opener`, НЕЗАВИСИМО друг от друга.

    Независимость — не стиль: вложенные снимки объявлены внутри
    `BackupArchive`, и проход, съедающий внешнее объявление целиком,
    не видит ни одного из них. Первая редакция так и сделала и дала
    «49 полей Dog из 49 не едут» при живом `DogSnapshot` — то есть
    круглое число, симптом разбора, а не находка.
    """
    lines = text.splitlines()
    found: dict[str, list[str]] = {}
    for i, line in enumerate(lines):
        m = opener.match(line)
        if m:
            found.setdefault(m.group("name"), body_at(lines, i))
    return found


MODEL_OPENER = re.compile(r"^\s*(?:final\s+)?class\s+(?P<name>\w+)")
STRUCT_OPENER = re.compile(r"^\s*(?:nonisolated\s+)?(?:public\s+)?struct\s+(?P<name>\w+)")


def model_bodies(text: str) -> dict[str, list[str]]:
    """Тела только тех классов, над которыми стоит `@Model`.

    Атрибут ищется на предыдущих непустых строках, а не на той же:
    `@Model` в этом проекте всегда стоит строкой выше, но между ним
    и классом может лежать документирующий комментарий.
    """
    lines = text.splitlines()
    marked: list[int] = []
    for n, line in enumerate(lines):
        if line.strip().startswith("@Model"):
            k = n + 1
            while k < len(lines) and (not lines[k].strip() or lines[k].strip().startswith("//")):
                k += 1
            if k < len(lines):
                marked.append(k)
    out: dict[str, list[str]] = {}
    for start in marked:
        chunk = "\n".join(lines[start:])
        got = bodies(chunk, MODEL_OPENER)
        if got:
            first = next(iter(got))
            out[first] = got[first]
    return out


def fields(body: list[str]) -> tuple[list[tuple[str, str]], list[tuple[str, str]]]:
    """(хранимые, не хранимые) — имя и тип. Не хранимые: вычисляемые
    (есть `{` после типа) и `static` (это не состояние записи).

    Атрибут `@Relationship` берётся и с предыдущей строки: в этом проекте
    он почти всегда стоит отдельной строкой над полем. Регулярка, не
    пускающая атрибут перед `var`, уже дважды испортила снимок схемы —
    поэтому атрибуты срезаются, а не запрещаются.
    """
    stored: list[tuple[str, str]] = []
    other: list[tuple[str, str]] = []
    pending_attr = ""
    for raw in body:
        line = strip_noise(raw)
        bare = line.strip()
        if bare.startswith("@") and "var" not in bare and "let" not in bare:
            pending_attr = bare
            continue
        if re.match(r"\s*(static|class)\s+", line):
            pending_attr = ""
            continue
        m = DECL.match(line)
        if not m:
            if bare:
                pending_attr = ""
            continue
        name = m.group("name")
        typ = (m.group("type") or "").strip()
        tail = (m.group("tail") or "").strip()
        attrs = (m.group("attrs") or "") + " " + pending_attr
        pending_attr = ""
        if tail.startswith("{"):
            other.append((name, typ))
        else:
            stored.append((name, typ + ("  @Relationship" if "@Relationship" in attrs else "")))
    return stored, other


def naked(typ: str) -> str:
    """Тип без обёрток: `[LogEvent]?` → `LogEvent`."""
    t = typ.split("@")[0].strip()
    return t.strip("?").strip("[]").strip("?").strip()


def structural(name: str, typ: str, model_names: set[str]) -> bool:
    """Поле — не данные, а место записи в дереве.

    Два признака, оба выводятся из разбора, а не из списка руками:
    `@Relationship` в атрибутах (дети, в архиве выражены вложенностью)
    и тип, который сам является `@Model` (ссылка на родителя — `dog`
    у одиннадцати моделей, `medication` у `DoseRecord`).

    Список руками знает только то, что в него положили: заведи завтра
    двенадцатую связь — он промолчит, а этот признак покраснеет.
    """
    return "@Relationship" in typ or naked(typ) in model_names


#: Закрытый набор суффиксов хранения. Модель держит сырое значение
#: (`sexRaw`, `doseSlotsData`), снимок — разобранное (`sex`, `doseSlots`);
#: это одно и то же поле. Набор закрытый и назван: открытое правило
#: «отбрось хвост» склеило бы разные поля.
#:
#: Цена каждого пункта измерена, а не предположена: без `Raw` сверка дала
#: бы ложные находки на верном коде, а `Data` дал одну настоящую ложную —
#: `doseSlotsData` против `doseSlots`, который едет в обе стороны
#: (`Backup.swift:145` и `:547`).
STORAGE_SUFFIXES = ("Raw", "Data", "Storage")


def base(name: str) -> str:
    for suffix in STORAGE_SUFFIXES:
        if name.endswith(suffix) and len(name) > len(suffix):
            return name[: -len(suffix)].lower()
    return name.lower()


def device_local(ref: str) -> set[str]:
    """Ключи `Модель.поле`, про которые ПРИНЯТО решение «только этот
    телефон». Читается из сторожа, а не хранится копией: копия числа
    меряет себя, а не мир."""
    try:
        text = read(ref, DEVICE_LOCAL_SOURCE)
    except Exception:
        return set()
    m = re.search(r'проЭтотТелефон[^=]*=\s*\[(.*?)\n\s*\]', text, re.S)
    if not m:
        return set()
    return set(re.findall(r'"(\w+\.\w+)"\s*:', m.group(1)))


def intentional(ref: str) -> set[str]:
    """Ключи `Модель.поле`, про которые ПРИНЯТО решение «в снимке нет
    намеренно». Читается из сторожа паритета, а не повторяется копией:
    копия расходится с реестром молча, а инструмент при этом докладывает
    уверенно. Поймано на себе — собственное решение про
    `awaitedMedicationID` этот инструмент назвал потерей."""
    try:
        text = read(ref, INTENTIONAL_SOURCE)
    except Exception:
        return set()
    m = re.search(r'вСнимкеНетНамеренно[^=]*=\s*\[(.*?)\n\s*\]', text, re.S)
    if not m:
        return set()
    return set(re.findall(r'"(\w+\.\w+)"\s*:', m.group(1)))


def snapshot_name(model: str, snaps: dict[str, list[str]]) -> str | None:
    """Имя снимка выводится из исходника; руками — только переименования."""
    direct = f"{model}Snapshot"
    if direct in snaps:
        return direct
    renamed = SNAPSHOT_RENAMED.get(model)
    return renamed if renamed in snaps else None


def measure(ref: str) -> dict:
    archive = read(ref, ARCHIVE_PATH)
    snaps = bodies(archive, STRUCT_OPENER)
    local = device_local(ref)
    решено = intentional(ref)

    models: dict[str, list[str]] = {}
    for path in list_files(ref, MODEL_GLOB):
        models.update(model_bodies(read(ref, path)))

    model_names = set(models)
    rows = []
    for model in sorted(models):
        stored, computed = fields(models[model])
        def kind(n: str, t: str) -> str:
            if structural(n, t, model_names):
                return "tree"
            if f"{model}.{n}" in решено:
                return "decided"
            if f"{model}.{n}" in local:
                return "phone"
            if n in SERVICE_FIELDS:
                return "service"
            return "data"

        data = [(n, t) for n, t in stored if kind(n, t) == "data"]
        service = [n for n, t in stored if kind(n, t) == "service"]
        phone = [n for n, t in stored if kind(n, t) == "phone"]
        decided = [n for n, t in stored if kind(n, t) == "decided"]
        tree = [n for n, t in stored if kind(n, t) == "tree"]

        snap_name = snapshot_name(model, snaps)
        if snap_name is None:
            rows.append({
                "model": model, "snapshot": "—",
                "data": data, "service": service, "phone": phone, "tree": tree,
                "decided": decided,
                "computed": computed,
                "in_snapshot": [], "missing": [n for n, _ in data],
                "missing_service": service, "no_snapshot": True,
            })
            continue
        snap_stored, _ = fields(snaps[snap_name])
        have = {base(n) for n, _ in snap_stored}
        rows.append({
            "model": model, "snapshot": snap_name,
            "data": data, "service": service, "phone": phone, "tree": tree,
                "decided": decided,
            "computed": computed,
            "in_snapshot": snap_stored,
            "missing": [n for n, _ in data if base(n) not in have],
            "missing_service": [n for n in service if base(n) not in have],
            "no_snapshot": False,
        })
    # Сирота — ЛЮБАЯ структура архива, которую не забрала ни одна модель,
    # кроме корневой. Проверять `endswith("Snapshot")` нельзя: подделка
    # переименовала `ProcedureSkillSnapshot` в `SkillSnap`, и сторож
    # остался зелёным — он искал по имени то, что обязан искать по месту.
    # Та же ошибка, что `hasPrefix("struct Swatch")` у Gamut.
    claimed = {r["snapshot"] for r in rows}
    orphans = sorted(n for n in snaps
                     if n not in claimed and n != "BackupArchive")
    return {"rows": rows, "models": models, "snaps": snaps,
            "decided_registry": решено,
            "orphan_snapshots": orphans, "device_local": local}


def blind(result: dict) -> list[str]:
    """Границы собственного зрения — проверяются ДО того, как назван
    хоть один недостающий список."""
    bad = []
    if len(result["models"]) < EXPECTED_MODEL_COUNT:
        bad.append(
            f"разобрано @Model: {len(result['models'])}, ожидалось "
            f"{EXPECTED_MODEL_COUNT} — разбор ослеп, список полей не назван"
        )
    snapshots = [n for n in result["snaps"] if n.endswith("Snapshot")]
    if len(snapshots) < MIN_SNAPSHOT_STRUCTS:
        bad.append(
            f"разобрано структур снимка: {len(snapshots)}, ожидалось "
            f"не меньше {MIN_SNAPSHOT_STRUCTS} — ослеп разбор архива"
        )
    orphans = [r["model"] for r in result["rows"] if r["no_snapshot"]]
    if len(orphans) > MAX_MODELS_WITHOUT_SNAPSHOT:
        bad.append(
            f"моделей без снимка: {len(orphans)} ({', '.join(orphans)}) — "
            "столько сразу не бывает, это разбор архива, а не находка"
        )
    if result["orphan_snapshots"]:
        bad.append(
            "снимки, которых не забрала ни одна модель: "
            + ", ".join(result["orphan_snapshots"])
            + " — либо отображение имён неверно, либо модель исчезла; "
              "в обоих случаях перечень ниже неполон"
        )
    if not result.get("decided_registry"):
        bad.append(
            f"реестр «в снимке нет намеренно» ({INTENTIONAL_SOURCE}) прочитан "
            "пустым — решённое будет названо потерей"
        )
    if not result["device_local"]:
        bad.append(
            f"реестр «только этот телефон» ({DEVICE_LOCAL_SOURCE}) прочитан "
            "пустым — device-local поля будут названы потерей"
        )
    for row in result["rows"]:
        total = len(row["data"]) + len(row["service"]) + len(row["tree"])
        if total < MIN_FIELDS_PER_MODEL:
            bad.append(
                f"{row['model']}: разобрано полей {total} — "
                "неправдоподобно мало, разбор ослеп на этой модели"
            )
        if not row["no_snapshot"] and not row["in_snapshot"]:
            bad.append(
                f"{row['model']} → {row['snapshot']}: снимок найден по имени, "
                "но полей в нём разобрано ноль — это разбор ослеп, "
                "а не снимок пуст"
            )
    return bad


def main() -> int:
    ap = argparse.ArgumentParser()
    # Умолчание — КОММИТ, а не рабочее дерево, и это не вкус.
    # В этом дереве одновременно пишут несколько сессий, и часть правок
    # в нём — чужие ПОДДЕЛКИ, внесённые ради приёмки чужого сторожа.
    # Замер по рабочему дереву в такую минуту отдаёт находки про работу,
    # которой через пять минут не будет. Предупреждение на этот случай
    # есть, но предупреждение читают, а умолчание действует.
    ap.add_argument("--ref", default="HEAD",
                    help="коммит (HEAD, хеш) или worktree — состояние замера; "
                         "по умолчанию HEAD, потому что дерево общее")
    ap.add_argument("--only", nargs="*", default=None,
                    help="только эти модели (по умолчанию все)")
    args = ap.parse_args()

    head = subprocess.run(["git", "--no-optional-locks", "rev-parse", "--short", "HEAD"],
                          cwd=ROOT, capture_output=True, text=True).stdout.strip()
    dirty = subprocess.run(["git", "--no-optional-locks", "status", "--short", "--",
                            ARCHIVE_PATH, "TogoShared/Models"],
                           cwd=ROOT, capture_output=True, text=True).stdout.strip()

    print(f"состояние замера   --ref {args.ref}   (HEAD {head})")
    if dirty:
        print("ВНИМАНИЕ: в измеряемых файлах есть незакоммиченные правки —")
        for line in dirty.splitlines():
            print(f"  {line}")
        if args.ref == "worktree":
            print("  И ТЫ МЕРИШЬ ИМЕННО ИХ. Часть правок в общем дереве — чужие")
            print("  подделки ради приёмки чужих сторожей: находка на таком поле")
            print("  говорит о подделке, а не о мире. Сверь с `--ref HEAD`.")
        else:
            print("  (мерю коммит, не их; но перечень младше дерева —")
            print("   кто-то правит эти же файлы прямо сейчас)")
    print()

    result = measure(args.ref)
    problems = blind(result)
    if problems:
        print("Я ОСЛЕП — списки не называю:")
        for p in problems:
            print(f"  {p}")
        return 2

    rows = result["rows"]
    if args.only:
        rows = [r for r in rows if r["model"] in args.only]

    print("Столбец «данных» — поля, которые ввёл человек. Из него вынесены:")
    print("  служ.    тождество `id` и метка слияния `changedAt`")
    print("  телеф.   решение «только этот телефон» — читается из реестра")
    print(f"           {DEVICE_LOCAL_SOURCE}, а не повторено здесь копией")
    print("  дерево   связи: в архиве выражены вложенностью, а не полем")
    print("Чистые модели стоят в перечне наравне с дырявыми — иначе это")
    print("список находок, а не перебор.")
    print()
    print(f"{'модель':<18}{'данных':>7}{'в снимке':>9}{'НЕ ЕДЕТ':>9}"
          f"{'служ.':>7}{'телеф.':>7}{'дерево':>8}   снимок")
    print("-" * 85)
    total_missing = 0
    for r in rows:
        total_missing += len(r["missing"])
        mark = "  ← СНИМКА НЕТ ВОВСЕ" if r["no_snapshot"] else ""
        flag = " ←" if r["missing"] and not r["no_snapshot"] else ""
        print(f"{r['model']:<18}{len(r['data']):>7}{len(r['in_snapshot']):>9}"
              f"{len(r['missing']):>9}{len(r['service']):>7}{len(r['phone']):>7}"
              f"{len(r['tree']):>8}   {r['snapshot']}{mark}{flag}")
    print("-" * 85)
    print(f"{'итого':<18}{sum(len(r['data']) for r in rows):>7}{'':>9}"
          f"{total_missing:>9}")
    print()

    clean = [r["model"] for r in rows if not r["missing"]]
    for r in rows:
        if not r["missing"]:
            continue
        where = "СНИМКА НЕТ ВОВСЕ" if r["no_snapshot"] else f"→ {r['snapshot']}"
        print(f"{r['model']} {where}: не едет {len(r['missing'])} из {len(r['data'])}")
        for n, t in r["data"]:
            if n in r["missing"]:
                print(f"    - {n}: {t}")
        if r["missing_service"]:
            print(f"    (служебное, тем же списком не считаю: "
                  f"{', '.join(r['missing_service'])})")
        if r["tree"]:
            print(f"    (связи дерева, в архиве выражены вложенностью: "
                  f"{', '.join(r['tree'])})")
        print()

    print(f"ЕДУТ ЦЕЛИКОМ ({len(clean)}): {', '.join(clean) or '—'}")
    print()
    print("ЧЕГО ЭТОТ ЗАМЕР НЕ ВИДИТ:")
    print("  · поле есть в снимке и НЕ ЗАПОЛНЯЕТСЯ при сборке архива —")
    print("    сверка идёт по ОБЪЯВЛЕНИЮ структуры, а не по Backup.swift")
    print("  · поле едет и восстанавливается не туда")
    print("  · потерю смысла: `note` там и `note` тут считаются одним полем")
    print("  · служебным я назвал `id` и `changedAt` РЕШЕНИЕМ, а не замером:")
    print("    если тождество записи кому-то нужно при восстановлении,")
    print("    этот столбец прячет настоящую потерю")
    print("  · соответствие модель → снимок выводится из исходника")
    print("    (`XSnapshot`), руками — только переименования; снимок,")
    print("    которого не забрала ни одна модель, валит замер целиком.")
    print("    Но ПЕРЕИМЕНОВАНИЕ, добавленное неверно, замер не поймает")
    print("  · «только этот телефон» берётся из реестра сторожа: решение,")
    print("    записанное там неверно, замер повторит, а не оспорит")
    return 0


if __name__ == "__main__":
    sys.exit(main())
