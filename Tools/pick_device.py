#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Печатает подключённый iPhone одной строкой: <devicectl-id> <udid> <имя>.

У устройства два разных идентификатора: devicectl знает своё, xcodebuild —
аппаратный UDID. Берём оба из одного json, чтобы не гадать.
"""

import json
import subprocess
import sys
import tempfile


def main():
    path = tempfile.mktemp(suffix=".json")
    subprocess.run(
        ["xcrun", "devicectl", "list", "devices", "--json-output", path],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
    )
    try:
        devices = json.load(open(path))["result"]["devices"]
    except Exception:
        sys.exit(1)

    for device in devices:
        hardware = device.get("hardwareProperties", {})
        connection = device.get("connectionProperties", {})
        if hardware.get("platform") != "iOS":
            continue
        if connection.get("pairingState") != "paired":
            continue
        # Симуляторы тоже «iOS» и тоже «paired»: без этой строки скрипт
        # выбирал «Gamut SE» и падал на «Transfer Files is not supported
        # by this device». Телефон приходит по сети или по проводу,
        # симулятор — всегда с этой же машины.
        if connection.get("transportType") == "sameMachine":
            continue
        print(device["identifier"],
              hardware.get("udid", ""),
              device.get("deviceProperties", {}).get("name", "iPhone"))
        return
    sys.exit(1)


if __name__ == "__main__":
    main()
