#!/bin/bash
# Отдаёт последнюю сборку тестировщикам: тексты и раздача.
#
#   Tools/publish_beta.sh
#
# Загрузка (`upload_testflight.sh`) сборку только приносит в App Store
# Connect. Пока её не добавили в группу, её не видит никто — даже свои.
# Это не очевидно и однажды уже стоило недели ожидания «почему не
# приходит»: сборки 25 и 30 так и остались ничьими.
#
# Скрипт делает три вещи: пишет «что тестировать», пишет заметки
# к сборке и добавляет её внутренней группе. Внешней группе сборку
# добавляет Apple после бета-ревью — см. submit_beta_review.sh.
#
# Два текста, и они разные:
#
#   testflight_description.txt   — «что тестировать» у приложения целиком.
#                                  Показывается один раз и меняется редко.
#   testflight_whats_new.txt     — заметки к последней сборке. Именно их
#                                  человек читает в TestFlight, нажимая
#                                  «Обновить».
#
# Тексты лежат в репозитории, а не только в дашборде Apple: иначе
# единственная копия живёт в браузере, её не видно в диффе и нельзя
# вернуть. Скрипт — способ доставить их туда, а не место их хранения.
#
# ВАЖНО, ГДЕ ЕГО ЗАПУСКАТЬ. Тексты берутся из дерева, в котором запущен
# скрипт, а сборка может быть собрана из ДРУГОГО дерева. 28.09 сборку
# 256 собирали из отдельного worktree на коммите, куда заметки к ней
# ещё не доехали: в дереве сборки лежали заметки к 248. Опубликовалось
# верное только потому, что скрипт запустили из основного репозитория.
#
# Ниже это проверяется: если заметки старше последнего коммита,
# который их трогал, — скрипт скажет вслух.
set -euo pipefail

# `ASC_ISSUER` против `ASC_ISSUER_ID` — расхождение имён между проектами.
#
# `Gamut/.env.asc` кладёт `ASC_ISSUER_ID`, этот скрипт ждал `ASC_ISSUER`
# и выходил с «не задан». Оба файла верны по отдельности; вместе их
# не запускал никто до 28.09, когда менеджер прогнал раздачу живьём
# и упёрся.
#
# Мост стоял в `upload_testflight.sh` с 23.09 — и только там.
# Починка на одной поверхности из трёх: тот же класс, что «перелёт»
# на автомобильной поездке сегодня утром.
if [ -z "${ASC_ISSUER:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ]; then
    ASC_ISSUER="$ASC_ISSUER_ID"
    export ASC_ISSUER
fi
: "${ASC_ISSUER:?не задан ни ASC_ISSUER, ни ASC_ISSUER_ID}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import json, os, glob, time, sys, urllib.request, urllib.error

key_path = glob.glob(os.path.expanduser("~/.appstoreconnect/private_keys/AuthKey_*.p8"))[0]
key_id = os.path.basename(key_path)[8:-3]
issuer = os.environ["ASC_ISSUER"]

try:
    import jwt
except ImportError:
    sys.exit("нужен PyJWT: python3 -m pip install pyjwt cryptography")

def token():
    now = int(time.time())
    return jwt.encode({"iss": issuer, "iat": now, "exp": now + 900,
                       "aud": "appstoreconnect-v1"},
                      open(key_path).read(), algorithm="ES256",
                      headers={"kid": key_id, "typ": "JWT"})

def call(path, method="GET", body=None):
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request("https://api.appstoreconnect.apple.com/v1/" + path,
                                 data=data, method=method)
    req.add_header("Authorization", "Bearer " + token())
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"App Store Connect ответил {e.code}: {e.read().decode()[:400]}")

def text(name):
    return open(f"fastlane/metadata/ru/{name}", encoding="utf-8").read().strip()

app = next(a for a in call("apps")["data"]
           if a["attributes"]["bundleId"] == "app.togo.diary")["id"]

# «Что тестировать» у приложения целиком.
loc = next(l for l in call(f"apps/{app}/betaAppLocalizations")["data"]
           if l["attributes"]["locale"] == "ru")
# Политика конфиденциальности — обязательное поле для внешнего теста.
# Пустое поле ревьюер возвращает с «missing privacy policy», а ссылка
# на несуществующий домен — с 5.1.1. Поэтому мёртвую сюда не пишем:
# лучше пусто и честно, чем ссылка, которая не открывается.
privacy = text("privacy_url.txt")
attributes = {"description": text("testflight_description.txt")}
if privacy.startswith("http") and "togo.app" not in privacy:
    attributes["privacyPolicyUrl"] = privacy
else:
    print(f"⚠︎ политика не проставлена: {privacy} — страницы нет. "
          "Сначала Tools/publish_site.sh")

call(f"betaAppLocalizations/{loc['id']}", "PATCH", {"data": {
    "type": "betaAppLocalizations", "id": loc["id"],
    "attributes": attributes}})
print("«что тестировать» обновлено"
      + (f", политика: {privacy}" if "privacyPolicyUrl" in attributes else ""))

# Заметки к последней сборке. Связь приложения сборок не отдаёт —
# спрашиваем фильтром.
builds = call(f"builds?filter[app]={app}&limit=1&sort=-uploadedDate")["data"]
if not builds:
    sys.exit("в App Store Connect нет ни одной сборки — сначала Tools/upload_testflight.sh")
build = builds[0]
print("сборка", build["attributes"]["version"], build["attributes"]["processingState"])

notes = text("testflight_whats_new.txt")

# Проверка «то ли мы ВЗЯЛИ», а не «то ли положили».
#
# Приёмка после действия отвечает на второй вопрос и слепа к первому:
# 28.09 в `testflight_whats_new.txt` лежал текст про сборку 80, когда
# роздана была 248. Скрипт отработал бы безупречно и опубликовал бы
# неправду, а перечитывание подтвердило бы, что опубликовано ровно то,
# что подано.
#
# Меряем так: если заметки, которые мы несём, СЛОВО В СЛОВО совпадают
# с заметками ПРЕДЫДУЩЕЙ сборки — почти наверняка файл не обновили.
# Это не доказательство, поэтому не падаем, а кричим и называем, что
# посмотреть.
предыдущие = call(f"builds?filter[app]={app}&limit=2&sort=-uploadedDate")["data"]
if len(предыдущие) > 1:
    прошлая = предыдущие[1]
    прошлые_тексты = [l["attributes"].get("whatsNew", "")
                      for l in call(f"builds/{прошлая['id']}/betaBuildLocalizations")["data"]
                      if l["attributes"]["locale"] == "ru"]
    if прошлые_тексты and прошлые_тексты[0].strip() == notes:
        print("⚠︎ ЗАМЕТКИ ТЕ ЖЕ, ЧТО У СБОРКИ "
              f"{прошлая['attributes']['version']} — похоже, файл не обновили.",
              file=sys.stderr)
        print("   fastlane/metadata/ru/testflight_whats_new.txt", file=sys.stderr)
        print("   Тексты берутся из дерева, В КОТОРОМ ЗАПУЩЕН скрипт, "
              "а сборка могла быть собрана из другого.", file=sys.stderr)

existing = [l for l in call(f"builds/{build['id']}/betaBuildLocalizations")["data"]
            if l["attributes"]["locale"] == "ru"]
if existing:
    call(f"betaBuildLocalizations/{existing[0]['id']}", "PATCH", {"data": {
        "type": "betaBuildLocalizations", "id": existing[0]["id"],
        "attributes": {"whatsNew": notes}}})
else:
    call("betaBuildLocalizations", "POST", {"data": {
        "type": "betaBuildLocalizations",
        "attributes": {"locale": "ru", "whatsNew": notes},
        "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}}}})
print("заметки к сборке обновлены")

# Раздача внутренней группе. Внешнюю не трогаем: добавление сборки
# туда требует пройденного бета-ревью, и делается это отдельно.
#
# ПРИЁМКА — ПЕРЕЧИТАННЫЙ СПИСОК ГРУППЫ, А НЕ КОД ОТВЕТА.
#
# До 28.09 здесь стояла форма «проверил ДО, напечатал ПОСЛЕ»: список
# версий читался перед `POST`, а «сборка выдана» печаталось сразу
# за ним, ничего не перечитывая. То есть скрипт сообщал о своём
# намерении, а не о том, что случилось.
#
# Повод не умозрительный, и он двойной.
#   1. 23.09 на Togo 141: `POST` ответил `204` на обеих группах,
#      и внешняя всё равно не видела ничего — состояние осталось
#      `READY_FOR_BETA_SUBMISSION`. Код ответа приёмкой не является.
#   2. 28.09 на Togo 248: внешняя группа получила сборку, а внутренняя
#      осталась на четырёхдневной 216 — и заметил это только тот,
#      кто перечитал списки обеих групп поимённо.
#
# Поэтому ниже печатается СПИСОК ВЕРСИЙ, полученный после действия.
# Напечатать «выдана», не перечитав, теперь нечем: строки такой нет.
def версии_группы(gid):
    return [b["attributes"]["version"]
            for b in call(f"betaGroups/{gid}/builds?limit=10")["data"]]

groups = call(f"apps/{app}/betaGroups")["data"]
internal = [g for g in groups if g["attributes"]["isInternalGroup"]]
if not internal:
    sys.exit("внутренней группы нет — заведи её в App Store Connect")

нужная = build["attributes"]["version"]
не_доехало = []

for group in internal:
    name = group["attributes"]["name"]
    if нужная in версии_группы(group["id"]):
        print(f"группа «{name}»: уже там · {версии_группы(group['id'])}")
        continue
    call(f"betaGroups/{group['id']}/relationships/builds", "POST", {"data": [
        {"type": "builds", "id": build["id"]}]})
    стало = версии_группы(group["id"])
    print(f"группа «{name}»: {стало}")
    if нужная not in стало:
        не_доехало.append(name)

# Внешние группы только ПОКАЗЫВАЕМ. Их наполняет бета-ревью, и трогать
# их отсюда нельзя, — но молчать о них тоже нельзя: 28.09 расхождение
# между «свои» и «друзья» было видно только рядом.
for group in groups:
    if group["attributes"]["isInternalGroup"]:
        continue
    name = group["attributes"]["name"]
    print(f"внешняя «{name}»: {версии_группы(group['id'])}  (наполняет бета-ревью)")

if не_доехало:
    sys.exit("НЕ РАЗДАНО после POST: " + ", ".join(не_доехало)
             + " — код ответа был успешным, а сборки в группе нет")
PY
