#!/bin/bash
# Доводит подписки в App Store Connect до состояния, в котором их видит
# приложение.
#
#   Tools/setup_subscriptions.sh
#
# Пока у подписки нет названия, описания, цены и территорий, она висит
# в состоянии MISSING_METADATA — и StoreKit её просто не отдаёт. В TestFlight
# это выглядит так: экран «Того Pro» открывается пустым, «Цены
# не загрузились». Пустое состояние в приложении предусмотрено и честное,
# но показывать его тестировщикам как норму нельзя.
#
# Тексты и цены берутся из fastlane/metadata/ru/subscriptions.json —
# в дашборде руками не вводится ничего.
#
# Скрипт идемпотентный: что уже заведено, он не трогает.
set -euo pipefail

: "${ASC_ISSUER:?не задан ASC_ISSUER}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import json, sys, time, os, glob, urllib.request, urllib.error

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

def call(path, method="GET", body=None, quiet=False):
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
        # Причина отказа лежит в теле, а не в коде: без неё «HTTP 409»
        # ничего не объясняет.
        text = e.read().decode()
        if quiet:
            return {"ERROR": e.code, "body": text}
        try:
            for err in json.loads(text)["errors"]:
                print(f"✗ {err.get('title')}: {err.get('detail')}", file=sys.stderr)
        except Exception:
            print(f"✗ HTTP {e.code}: {text[:300]}", file=sys.stderr)
        sys.exit(1)

plan = json.load(open("fastlane/metadata/ru/subscriptions.json", encoding="utf-8"))
LOCALE = "ru"

app = next(a for a in call("apps")["data"]
           if a["attributes"]["bundleId"] == "app.togo.diary")["id"]
groups = call(f"apps/{app}/subscriptionGroups?include=subscriptions")
group = groups["data"][0]
subs = {s["attributes"]["productId"]: s for s in groups["included"]}

# 1. Имя группы. Его человек видит в системных настройках подписок,
#    когда выбирает между планами.
have = [l for l in call(f"subscriptionGroups/{group['id']}/subscriptionGroupLocalizations")["data"]
        if l["attributes"]["locale"] == LOCALE]
if have:
    print("группа: имя уже есть")
else:
    call("subscriptionGroupLocalizations", "POST", {"data": {
        "type": "subscriptionGroupLocalizations",
        "attributes": {"name": plan["groupName"], "locale": LOCALE},
        "relationships": {"subscriptionGroup": {
            "data": {"type": "subscriptionGroups", "id": group["id"]}}}}})
    print(f"группа: имя «{plan['groupName']}» записано")

territories = [t["id"] for t in call("territories?limit=200")["data"]]

for product_id, wanted in plan["products"].items():
    sub = subs.get(product_id)
    if sub is None:
        sys.exit(f"в App Store Connect нет подписки {product_id}")
    sid = sub["id"]
    print(f"\n{product_id}")

    # 2. Название и описание. Ограничения Apple: 30 и 45 знаков.
    have = [l for l in call(f"subscriptions/{sid}/subscriptionLocalizations")["data"]
            if l["attributes"]["locale"] == LOCALE]
    if have:
        print("  название и описание уже есть")
    else:
        call("subscriptionLocalizations", "POST", {"data": {
            "type": "subscriptionLocalizations",
            "attributes": {"name": wanted["name"],
                           "description": wanted["description"],
                           "locale": LOCALE},
            "relationships": {"subscription": {
                "data": {"type": "subscriptions", "id": sid}}}}})
        print(f"  название «{wanted['name']}» записано")

    # 3. Где продаётся. Без этого подписка нигде не доступна.
    current = call(f"subscriptions/{sid}/subscriptionAvailability", quiet=True)
    if current.get("data"):
        print("  территории уже заданы")
    else:
        call("subscriptionAvailabilities", "POST", {"data": {
            "type": "subscriptionAvailabilities",
            "attributes": {"availableInNewTerritories": True},
            "relationships": {
                "subscription": {"data": {"type": "subscriptions", "id": sid}},
                "availableTerritories": {"data": [
                    {"type": "territories", "id": t} for t in territories]}}}})
        print(f"  территории: все {len(territories)}")

    # 4. Цена. Задаётся одной опорной территорией — остальные Apple
    #    считает сама по своей таблице.
    if call(f"subscriptions/{sid}/prices?limit=1")["data"]:
        print("  цена уже задана")
        continue

    base = plan["baseTerritory"]
    points = call(f"subscriptions/{sid}/pricePoints?filter[territory]={base}&limit=200")["data"]
    point = next((p for p in points
                  if p["attributes"]["customerPrice"] == wanted["price"]), None)
    if point is None:
        sys.exit(f"  нет точки цены {wanted['price']} для {base} — "
                 "поправь цену в subscriptions.json")

    call("subscriptionPrices", "POST", {"data": {
        "type": "subscriptionPrices",
        "attributes": {"preserveCurrentPrice": False},
        "relationships": {
            "subscription": {"data": {"type": "subscriptions", "id": sid}},
            "subscriptionPricePoint": {
                "data": {"type": "subscriptionPricePoints", "id": point["id"]}}}}})
    print(f"  цена {wanted['price']} ({base}) записана")

print("\n── состояние")
for s in call(f"apps/{app}/subscriptionGroups?include=subscriptions")["included"]:
    a = s["attributes"]
    print(f"  {a['productId']}: {a['state']}")
print("""
MISSING_METADATA — чего-то ещё не хватает; смотри карточку подписки
в App Store Connect. Скриншот для ревью через API не загрузить: он нужен
перед отправкой в App Review, но не мешает подписке грузиться в TestFlight.""")
PY
