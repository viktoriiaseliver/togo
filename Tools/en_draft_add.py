#!/usr/bin/env python3
"""Влить партию английского в черновик: `python3 Tools/en_draft_add.py < patch.json`.

Патч — объект «русский ключ → английская строка» или «→ {one, other}»
для ключей с формами числа. Помеченный пробел — `{"__ПРОБЕЛ__": "почему"}`.

Проверяет на входе и ОТКАЗЫВАЕТСЯ писать партию целиком, если в ней есть
ключ, которого нет в каталоге: иначе опечатка в ключе уехала бы молча
и выглядела бы переводом.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import en_draft as base  # noqa: E402

patch = json.load(sys.stdin)
cat = base.catalog()
unknown = [k for k in patch if k not in cat]
if unknown:
    print(f"✘ ключей нет в каталоге: {len(unknown)}")
    for k in unknown[:10]:
        print("  •", repr(k[:80]))
    sys.exit(1)

have = base.draft()
again = sorted(set(patch) & set(have))
have.update(patch)
base.save(have)
print(f"влито {len(patch)}, перезаписано {len(again)}, в черновике {len(have)}")
if again:
    for k in again[:5]:
        print("  перезаписан:", k[:70])
