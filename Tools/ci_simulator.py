# -*- coding: utf-8 -*-
"""Найти симулятор для прогона тестов — или завести его.

**Зачем.** В `ci.yml` назначение называлось именем устройства:
`platform=iOS Simulator,name=iPhone 17 Pro`. Имя — ловушка. Прогоны
#44 и #45 от 21.09.2026 выбрали ОДИН И ТОТ ЖЕ Xcode 26.3 (17C529):
первый прошёл за 12 минут, второй упал за полторы с

    Unable to find a device matching the provided destination specifier:
        { platform:iOS Simulator, OS:latest, name:iPhone 17 Pro }

и списком, в котором из симуляторов остались только заглушки
«Any iOS Simulator Device». То есть машина образа на машину образа
не приходится: где-то устройство зарегистрировано, где-то нет.
Красный при этом выглядел как «сломал тот, кто последним пушил».

Поэтому устройство здесь **ищется, а не называется**, а если готового
нет — заводится. Печатает UDID в stdout; всё остальное идёт в stderr,
чтобы вывод можно было подставить прямо в назначение.

    python3 Tools/ci_simulator.py        # → UDID

Не нашлось и завести не удалось — выходим с ненулевым кодом и печатаем
ВСЁ, что видно: среды выполнения, типы устройств, сам Xcode. Молчаливое
падение здесь дороже длинного лога: именно из-за него красный CI
провисел незамеченным с обновления образа.
"""
import json
import re
import subprocess
import sys


def simctl(*args):
    out = subprocess.check_output(["xcrun", "simctl", "list", *args, "--json"])
    return json.loads(out)


def версия(строка):
    """`com.apple.CoreSimulator.SimRuntime.iOS-26-2` → (26, 2)."""
    числа = re.findall(r"\d+", строка.rsplit(".", 1)[-1])
    return tuple(int(n) for n in числа)


# То же устройство, что стоит в `DESTINATION` Makefile. Совпадение
# с локальным прогоном не обязательно, но когда оно достижимо — лучше
# совпасть: разбирать расхождение «у меня зелено, в CI красно» дороже.
ЖЕЛАЕМОЕ = "iPhone 17 Pro"


def готовое_устройство():
    """Желаемый iPhone, а если его нет — самый новый из доступных."""
    девайсы = simctl("devices", "available")["devices"]
    лучшее = None
    for runtime, список in девайсы.items():
        if "iOS" not in runtime:
            continue
        for dev in список:
            if not dev.get("isAvailable") or "iPhone" not in dev.get("name", ""):
                continue
            ключ = (dev["name"] == ЖЕЛАЕМОЕ, версия(runtime), dev["name"])
            if лучшее is None or ключ > лучшее[0]:
                лучшее = (ключ, dev["udid"], runtime, dev["name"])
    return лучшее


def завести():
    """Готовых нет — собрать свой из самой новой доступной среды."""
    среды = [r for r in simctl("runtimes")["runtimes"]
             if r.get("isAvailable") and "iOS" in r.get("name", "")]
    if not среды:
        return None
    среда = max(среды, key=lambda r: версия(r["identifier"]))

    типы = [t for t in simctl("devicetypes")["devicetypes"]
            if "iPhone" in t.get("name", "")]
    # Фильтр по `supportedDeviceTypes` был мёртвым: `… or True` истинно
    # всегда, и условие слева не значило ничего. Оставлен честный перебор
    # всех типов iPhone — `supportedDeviceTypes` есть не во всех версиях
    # simctl, и создание само скажет, подходит тип или нет.
    подходящие = типы

    # Сортировка по ИМЕНИ ставила «iPhone Xʀ» выше «iPhone 17 Pro», потому
    # что лексикографически «X» больше «1»: запасной путь заводил старое
    # устройство, а кадры приёмки сняты на 17 Pro. Сортируем по числу
    # в имени, а слова — на своих местах.
    def новизна(t):
        цифры = [int(ч) for ч in re.findall(r"\d+", t["name"])]
        return (max(цифры) if цифры else 0, t["name"])

    for тип in sorted(подходящие, key=новизна, reverse=True):
        try:
            udid = subprocess.check_output(
                ["xcrun", "simctl", "create", "ci-iphone",
                 тип["identifier"], среда["identifier"]],
                stderr=subprocess.DEVNULL).decode().strip()
        except subprocess.CalledProcessError:
            continue
        return udid, среда["name"], тип["name"]
    return None


def сдаться():
    print("Симулятора для прогона нет, и завести не вышло.", file=sys.stderr)
    for заголовок, args in (("Среды выполнения", ["runtimes"]),
                            ("Типы устройств", ["devicetypes"]),
                            ("Устройства", ["devices", "available"])):
        print(f"\n── {заголовок}", file=sys.stderr)
        subprocess.run(["xcrun", "simctl", "list", *args], stderr=sys.stderr)
    subprocess.run(["xcodebuild", "-version"], stderr=sys.stderr)
    sys.exit(1)


готовое = готовое_устройство()
if готовое:
    _, udid, runtime, имя = готовое
    print(f"Беру готовый: {имя} · {runtime}", file=sys.stderr)
    print(udid)
    sys.exit(0)

создано = завести()
if создано:
    udid, среда, тип = создано
    print(f"Готовых не было, завёл: {тип} · {среда}", file=sys.stderr)
    print(udid)
    sys.exit(0)

сдаться()
