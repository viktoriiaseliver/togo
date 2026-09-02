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
set -euo pipefail

: "${ASC_ISSUER:?не задан ASC_ISSUER}"

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
internal = [g for g in call(f"apps/{app}/betaGroups")["data"]
            if g["attributes"]["isInternalGroup"]]
if not internal:
    sys.exit("внутренней группы нет — заведи её в App Store Connect")

for group in internal:
    name = group["attributes"]["name"]
    have = {b["attributes"]["version"]
            for b in call(f"betaGroups/{group['id']}/builds?limit=10")["data"]}
    if build["attributes"]["version"] in have:
        print(f"группа «{name}»: сборка уже там")
        continue
    call(f"betaGroups/{group['id']}/relationships/builds", "POST", {"data": [
        {"type": "builds", "id": build["id"]}]})
    print(f"группа «{name}»: сборка выдана")
PY
