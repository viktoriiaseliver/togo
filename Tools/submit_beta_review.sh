#!/bin/bash
# Отправляет последнюю сборку на бета-ревью для внешних тестировщиков.
#
#   Tools/submit_beta_review.sh "+33 6 12 34 56 78"
#
# Телефон контактного лица Apple требует отдельным обязательным полем.
# Без него запрос отклоняется с ENTITY_ERROR.ATTRIBUTE.REQUIRED —
# это единственное, что мешает отправить сборку внешней группе.
set -euo pipefail

PHONE="${1:?укажи телефон контактного лица: Tools/submit_beta_review.sh \"+33 6 ...\"}"
: "${ASC_ISSUER:?не задан ASC_ISSUER}"

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

call(f"betaAppReviewDetails/{app}", "PATCH", {"data": {
    "type": "betaAppReviewDetails", "id": app,
    "attributes": {"contactPhone": phone}}})
print("телефон записан")

build = call(f"apps/{app}/builds?limit=1&sort=-uploadedDate")["data"][0]
print("сборка", build["attributes"]["version"], build["attributes"]["processingState"])

call("betaAppReviewSubmissions", "POST", {"data": {
    "type": "betaAppReviewSubmissions",
    "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}}}})
print("отправлено на бета-ревью — обычно сутки")
PY
