#!/usr/bin/env python3
"""Завести или обновить локаль витрины в App Store Connect из fastlane/metadata.

    source ../Gamut/.env.asc
    python3 Tools/asc_storefront_locale.py en-US --dry
    python3 Tools/asc_storefront_locale.py en-US --write

Почему скриптом, а не руками в браузере: состояние витрины живёт вне git,
и единственный способ сказать о нём правду — спросить API и напечатать
ответ. Руками сделанное нечем перепроверить через месяц.

Два правила проекта вшиты внутрь:

1. **Ни один код ответа не предсказывает исход.** После записи скрипт
   всегда спрашивает состояние отдельным запросом и печатает то, что
   пришло, а не то, что отправлял. Замерено на Togo 141 (`204` без
   раздачи) и Timer 219 (`422` при успехе).
2. **Без `--write` ничего не отправляется.** Граница разрешений
   проходит через этот скрипт, поэтому за неё нельзя зайти случайно:
   по умолчанию только читает и показывает длины полей.

Имена переменных только латиницей: `Д="файл"` в оболочке не заводится
молча, и это уже стоило проекту рабочего файла.
"""
import glob
import json
import os
import sys
import time
import urllib.error
import urllib.request

APP_ID = "6805876636"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Поле каталога → (файл в fastlane/metadata, лимит Apple).
# Лимиты из `references/app-store-fields.md` скилла seo-optimizer.
INFO_FIELDS = {
    "name": ("name.txt", 30),
    "subtitle": ("subtitle.txt", 30),
    "privacyPolicyUrl": ("privacy_url.txt", 255),
}
VERSION_FIELDS = {
    "description": ("description.txt", 4000),
    "keywords": ("keywords.txt", 100),
    "promotionalText": ("promotional_text.txt", 170),
    "supportUrl": ("support_url.txt", 255),
}


def token():
    key_path = glob.glob(os.path.expanduser("~/.appstoreconnect/private_keys/AuthKey_*.p8"))
    if not key_path:
        sys.exit("нет ключа ASC в ~/.appstoreconnect/private_keys/AuthKey_*.p8")
    key_path = key_path[0]
    key_id = os.path.basename(key_path)[8:-3]
    # Gamut/.env.asc кладёт ASC_ISSUER_ID, скрипты Togo исторически ждали
    # ASC_ISSUER. Оба файла верны по отдельности; вместе их не запускал
    # никто — поэтому принимаем любое из двух имён.
    issuer = os.environ.get("ASC_ISSUER_ID") or os.environ.get("ASC_ISSUER")
    if not issuer:
        sys.exit("нет ASC_ISSUER_ID (или ASC_ISSUER): source Gamut/.env.asc")
    try:
        import jwt
    except ImportError:
        sys.exit("нужен PyJWT: python3 -m pip install pyjwt cryptography")
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
        with urllib.request.urlopen(req) as response:
            raw = response.read()
            return response.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as error:
        # Apple объясняет отказ в теле, а не в коде: без этого
        # «HTTP Error 409» — стек питона вместо причины.
        try:
            body = json.loads(error.read())
            for item in body.get("errors", []):
                print(f"  ✗ {error.code} {item.get('title')}: {item.get('detail')}",
                      file=sys.stderr)
        except Exception:
            print(f"  ✗ HTTP {error.code}", file=sys.stderr)
        return error.code, None


def read_fields(locale, fields):
    out = {}
    for key, (name, limit) in fields.items():
        path = os.path.join(ROOT, "fastlane", "metadata", locale, name)
        if not os.path.exists(path):
            continue
        value = open(path, encoding="utf-8").read().strip()
        if len(value) > limit:
            sys.exit(f"{locale}/{name}: {len(value)} знаков при лимите {limit}")
        out[key] = value
        print(f"  {key:16} {len(value):4} / {limit}")
    return out


def upsert(kind, parent_type, parent_id, locale, attributes, write):
    """Создать локализацию или обновить существующую."""
    status, existing = call(f"{parent_type}/{parent_id}/{kind}")
    if existing is None:
        sys.exit(f"не прочитать {kind}: запрос не состоялся")
    mine = [x for x in existing["data"] if x["attributes"]["locale"] == locale]
    if not write:
        print(f"  --dry: {'обновила бы' if mine else 'создала бы'} {kind} {locale}")
        return None
    if mine:
        code, _ = call(f"{kind}/{mine[0]['id']}", "PATCH", {
            "data": {"type": kind, "id": mine[0]["id"], "attributes": attributes}})
        print(f"  PATCH {kind} → {code}")
    else:
        code, _ = call(kind, "POST", {"data": {
            "type": kind, "attributes": dict(attributes, locale=locale),
            "relationships": {parent_type[:-1] if parent_type.endswith("s") else parent_type: {
                "data": {"type": parent_type, "id": parent_id}}}}})
        print(f"  POST {kind} → {code}")
    return True


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    locale = sys.argv[1]
    write = "--write" in sys.argv

    status, infos = call(f"apps/{APP_ID}/appInfos")
    if infos is None:
        sys.exit("не прочитать appInfos")
    info = infos["data"][0]
    status, versions = call(f"apps/{APP_ID}/appStoreVersions?limit=1")
    version = versions["data"][0]
    print(f"приложение {APP_ID}")
    print(f"  appInfo        {info['id']}  {info['attributes']['state']}")
    print(f"  версия         {version['attributes']['versionString']}  "
          f"{version['attributes']['appStoreState']}")

    print(f"\nполя {locale} из fastlane/metadata:")
    info_attrs = read_fields(locale, INFO_FIELDS)
    version_attrs = read_fields(locale, VERSION_FIELDS)
    if not info_attrs or not version_attrs:
        sys.exit(f"нет текстов в fastlane/metadata/{locale}")

    print("\nзапись:" if write else "\nпроверка без записи:")
    upsert("appInfoLocalizations", "appInfos", info["id"], locale, info_attrs, write)
    upsert("appStoreVersionLocalizations", "appStoreVersions", version["id"],
           locale, version_attrs, write)

    # Приёмка — отдельный запрос состояния, а не код ответа.
    print("\nсостояние после (отдельным запросом):")
    for kind, parent_type, parent_id in (
            ("appInfoLocalizations", "appInfos", info["id"]),
            ("appStoreVersionLocalizations", "appStoreVersions", version["id"])):
        _, got = call(f"{parent_type}/{parent_id}/{kind}")
        locales = sorted(x["attributes"]["locale"] for x in (got or {}).get("data", []))
        print(f"  {kind}: {locales}")
        for item in (got or {}).get("data", []):
            if item["attributes"]["locale"] != locale:
                continue
            for key in list(INFO_FIELDS) + list(VERSION_FIELDS):
                value = item["attributes"].get(key)
                if value is None:
                    continue
                print(f"    {key:16} {len(value):4} знаков: {value[:60]!r}")


if __name__ == "__main__":
    main()
