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

# Телефон контактного лица — из файла рядом с ключом, а не из аргумента.
#
# Аргумент означает, что его набирают руками каждый раз, и однажды
# наберут неверный: ревьюер Apple звонит по нему, и ошибка вскроется
# отказом, а не опечаткой. Файл лежит там же, где ключ, то есть
# вне репозитория — персональные данные в git не едут.
#
# Аргумент остаётся и побеждает файл: разовая замена нужна.
PHONE_FILE="${PHONE_FILE:-$HOME/.appstoreconnect/contact_phone.txt}"
PHONE="${1:-}"
if [ -z "$PHONE" ] && [ -f "$PHONE_FILE" ]; then
    PHONE="$(tr -d '\r\n' < "$PHONE_FILE")"
fi
if [ -z "$PHONE" ]; then
    echo "Нет телефона контактного лица." >&2
    echo "Положи его в $PHONE_FILE или передай аргументом:" >&2
    echo "  Tools/submit_beta_review.sh \"+33 6 12 34 56 78\"" >&2
    exit 1
fi
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
export CONTACT_FIRST="${CONTACT_FIRST:-Viktoriia}"
export CONTACT_LAST="${CONTACT_LAST:-Seliverstova}"
export CONTACT_EMAIL="${CONTACT_EMAIL:-viktoriia.seliver@gmail.com}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 - "$PHONE" <<'PY'
import json, sys, time, urllib.request, urllib.error, os, glob

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
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        # Apple объясняет отказ в теле ответа, а не в коде. Без этого
        # «HTTP Error 422» — это стек питона вместо причины.
        try:
            for err in json.loads(e.read())["errors"]:
                print(f"✗ {err.get('title')}: {err.get('detail')}", file=sys.stderr)
        except Exception:
            print(f"✗ HTTP {e.code}", file=sys.stderr)
        sys.exit(1)

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
        # Аккаунта в приложении нет вовсе — ревьюеру нечего давать,
        # и сказать об этом надо явно, иначе он ждёт демо-доступ.
        "demoAccountRequired": False,
        "notes": open("fastlane/metadata/ru/review_notes.txt",
                      encoding="utf-8").read().strip(),
    }}})
print("контактное лицо и заметка для ревьюера записаны")

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

# ПРИЁМКА — ПЕРЕЧИТАННОЕ `externalBuildState`, А НЕ КОД ОТВЕТА.
#
# Раньше здесь печаталось «отправлено на бета-ревью — обычно сутки»
# сразу за `POST`. Это сообщение о намерении: тот же `POST` 23.09
# на сборке 141 отвечал успехом, а внешняя группа не видела ничего.
#
# И «обычно сутки» — тоже не всегда правда: если версия бета-ревью
# уже проходила, следующие сборки той же версии идут насквозь
# и состояние становится `IN_BETA_TESTING` сразу. Печатать срок,
# которого не знаешь, значит учить не верить сроку.
after = call(f"builds/{build['id']}/buildBetaDetail")
state = (after.get("data", {}).get("attributes", {})
         .get("externalBuildState", "не прочитано"))
print("externalBuildState:", state)

def версии(gid):
    return [b["attributes"]["version"]
            for b in call(f"betaGroups/{gid}/builds?limit=10")["data"]]

if state == "IN_BETA_TESTING":
    # `IN_BETA_TESTING` — ЭТО НЕ «РОЗДАНО».
    #
    # Состояние говорит, что бета-ревью пройдено и сборку МОЖНО дать
    # внешним. В группу её при этом не кладёт никто: 28.09 на сборке
    # 271 состояние было `IN_BETA_TESTING`, а в «Друзьях» лежала 258.
    # Тем же днём это уже ловили руками на 248 — и чинили тоже руками,
    # то есть в следующий раз поймали бы снова.
    #
    # Зеркало правила, которое у нас записано с 23.09 про код ответа:
    # там `204` не значил «раздано», здесь `IN_BETA_TESTING` не значит
    # «у людей». Приёмка одна и та же — перечитанный список группы.
    внешние = [g for g in call(f"apps/{app}/betaGroups")["data"]
               if not g["attributes"]["isInternalGroup"]]
    не_доехало = []
    for g in внешние:
        имя = g["attributes"]["name"]
        if build["attributes"]["version"] in версии(g["id"]):
            print(f"внешняя «{имя}»: уже там · {версии(g['id'])}")
            continue
        call(f"betaGroups/{g['id']}/relationships/builds", "POST",
             {"data": [{"type": "builds", "id": build["id"]}]})
        стало = версии(g["id"])
        print(f"внешняя «{имя}»: {стало}")
        if build["attributes"]["version"] not in стало:
            не_доехало.append(имя)
    if не_доехало:
        sys.exit("НЕ РАЗДАНО внешним после POST: " + ", ".join(не_доехало)
                 + " — код ответа был успешным, а сборки в группе нет")
    print("внешние тестировщики видят сборку уже сейчас")
elif state in ("WAITING_FOR_BETA_REVIEW", "IN_BETA_REVIEW"):
    print("на бета-ревью — этой версии оно нужно впервые, обычно сутки")
else:
    # Не падаем: состояние могло не успеть обновиться. Но и не говорим
    # «отправлено» — говорим ровно то, что прочитали, и что делать.
    print(f"состояние пока «{state}» — перечитай через минуту:", file=sys.stderr)
    print(f"  GET builds/{build['id']}/buildBetaDetail", file=sys.stderr)
PY
