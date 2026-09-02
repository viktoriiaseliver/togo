#!/bin/bash
# Отправляет последнюю сборку на бета-ревью для внешних тестировщиков.
#
#   Tools/submit_beta_review.sh "+33 6 12 34 56 78"
#
# Контактное лицо Apple требует четырьмя обязательными полями: имя,
# фамилия, почта и телефон. Без любого из них запрос отклоняется
# с ENTITY_ERROR.ATTRIBUTE.REQUIRED. Имя, фамилия и почта берутся
# из окружения и имеют разумные значения по умолчанию; телефон вывести
# неоткуда, поэтому он аргументом.
#
#   CONTACT_FIRST, CONTACT_LAST, CONTACT_EMAIL — если надо иначе
set -euo pipefail

PHONE="${1:?укажи телефон контактного лица: Tools/submit_beta_review.sh \"+33 6 ...\"}"
: "${ASC_ISSUER:?не задан ASC_ISSUER}"
export CONTACT_FIRST="${CONTACT_FIRST:-Viktoriia}"
export CONTACT_LAST="${CONTACT_LAST:-Seliverstova}"
export CONTACT_EMAIL="${CONTACT_EMAIL:-viktoriia.seliver@gmail.com}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 - "$PHONE" <<'PY'
import json, sys, time, urllib.request, subprocess, os, glob

phone = sys.argv[1]
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
    url = "https://api.appstoreconnect.apple.com/v1/" + path
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token())
    if data:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req) as r:
        raw = r.read()
        return json.loads(raw) if raw else {}

app = next(a for a in call("apps")["data"]
           if a["attributes"]["bundleId"] == "app.togo.diary")["id"]

# Все четыре поля разом. Раньше сюда уходил только телефон, а пустыми
# были и имя, и фамилия, и почта — запрос отклонялся ровно так же,
# и выглядело это как «телефон не подошёл».
call(f"betaAppReviewDetails/{app}", "PATCH", {"data": {
    "type": "betaAppReviewDetails", "id": app,
    "attributes": {
        "contactFirstName": os.environ["CONTACT_FIRST"],
        "contactLastName": os.environ["CONTACT_LAST"],
        "contactEmail": os.environ["CONTACT_EMAIL"],
        "contactPhone": phone,
        "demoAccountRequired": False,
    }}})
print("контактное лицо записано")

# Сборки спрашиваем фильтром, а не связью приложения: связь отдаёт
# пустой список, и скрипт падал на выборе первой сборки.
builds = call(f"builds?filter[app]={app}&limit=1&sort=-uploadedDate")["data"]
if not builds:
    sys.exit("в App Store Connect нет ни одной сборки — сначала Tools/upload_testflight.sh")
build = builds[0]
state = build["attributes"]["processingState"]
print("сборка", build["attributes"]["version"], state)
if state != "VALID":
    sys.exit(f"сборка ещё в обработке ({state}) — подожди и повтори")

call("betaAppReviewSubmissions", "POST", {"data": {
    "type": "betaAppReviewSubmissions",
    "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}}}})
print("отправлено на бета-ревью — обычно сутки")
PY
