#!/usr/bin/env python3
"""Иконка приложения.

ИСТОЧНИК ИКОНКИ СМЕНИЛСЯ 08.10.2026. ЭТОТ СКРИПТ БОЛЬШЕ НЕ ОН.

    было   `draw_icon.py` рисует кодом → вывод уезжает в ассеты
    стало  иконку нарисовала Виктория в Icon Composer, экспорт
           лежит в `~/Downloads/Togo Exports` (110 файлов, семь
           семейств). В ассеты уезжает ЕЁ экспорт

Скрипт оставлен нарочно, а не удалён: он помнит мотив и палитру,
и по нему видно, чем иконка была. Но **не запускай его в ассеты** —
его вывод перезапишет её работу, и перезапишет молча: файл тот же,
размер тот же, в `git status` одна строка.

Довод прежней редакции («рисуется кодом, потому что править вслепую
невозможно») отменён тем, что у иконки появился настоящий исходник
и человек, который им владеет. Исходник в Icon Composer, не здесь.

Что из прежнего текста осталось верным и стоит прочесть: мотив,
палитра и мерка «силуэт узнаётся с 40 точек» — ей и принимают
новую иконку.

---

Рисуется кодом, а не лежит бинарником: иконку приходится править —
подвинуть ухо, сменить оттенок, — и делать это вслепую в редакторе,
не имея исходника, невозможно.

Мотив: пёс в профиль. Не лапа и не косточка — их рисуют все, и в папке
приложений такая иконка теряется. Силуэт узнаётся с 40 точек, а именно
столько занимает иконка в поиске.

Палитра — та же, что в приложении: тёплая бумага, чернила, охра
на ошейнике. Никакого градиента и никакой тени: макет собран под бумагу.

    python3 Tools/draw_icon.py
"""

import math
import struct
import zlib
from pathlib import Path

SIZE = 1024
SS = 3                      # сглаживание: рисуем крупнее и ужимаем
W = SIZE * SS

PAPER = (0xFA, 0xF7, 0xF0)
INK = (0x22, 0x1E, 0x18)
OCHRE = (0xC8, 0x7F, 0x3C)
SAND = (0xE5, 0xDD, 0xCE)


def wobble(seed: int, amount: float = 0.014):
    """Лёгкая неровность контура — чтобы силуэт читался нарисованным,
    а не построенным по формуле. Амплитуда маленькая намеренно:
    на маленьком размере кривой контур превращается в грязь."""
    phase = [(seed * (i + 3) % 17) / 17 * math.tau for i in range(3)]

    def at(angle: float) -> float:
        value = (math.sin(angle * 2 + phase[0])
                 + 0.6 * math.sin(angle * 3 + phase[1])
                 + 0.4 * math.sin(angle * 5 + phase[2]))
        return 1 + amount * value / 2

    return at


class Mask:
    """Силуэт собирается отдельно от цвета.

    Так ошейник можно положить строго внутрь собаки, а не поверх неё:
    в первой попытке он торчал наружу прямоугольником и читался
    как посторонняя палка."""

    def __init__(self):
        self.bits = bytearray(W * W)

    def blob(self, cx, cy, rx, ry, rotation=0.0, seed=1, amount=0.014, value=1):
        cx, cy, rx, ry = cx * SS, cy * SS, rx * SS, ry * SS
        jitter = wobble(seed, amount)
        cos_r, sin_r = math.cos(-rotation), math.sin(-rotation)
        reach = int(max(rx, ry) * 1.12) + 2

        for y in range(max(0, int(cy) - reach), min(W, int(cy) + reach)):
            dy = y - cy
            row = y * W
            for x in range(max(0, int(cx) - reach), min(W, int(cx) + reach)):
                dx = x - cx
                ux = dx * cos_r - dy * sin_r
                uy = dx * sin_r + dy * cos_r
                scale = jitter(math.atan2(uy, ux))
                if (ux / (rx * scale)) ** 2 + (uy / (ry * scale)) ** 2 <= 1:
                    self.bits[row + x] = value

    def band(self, cx, cy, half_width, half_height, rotation=0.0, only_inside=None, value=2):
        """Прямая полоса. С `only_inside` кладётся лишь туда,
        где силуэт уже есть, — то есть обрезается по собаке."""
        cx, cy = cx * SS, cy * SS
        half_width, half_height = half_width * SS, half_height * SS
        cos_r, sin_r = math.cos(-rotation), math.sin(-rotation)
        reach = int(max(half_width, half_height) * 1.6) + 2

        for y in range(max(0, int(cy) - reach), min(W, int(cy) + reach)):
            dy = y - cy
            row = y * W
            for x in range(max(0, int(cx) - reach), min(W, int(cx) + reach)):
                dx = x - cx
                ux = dx * cos_r - dy * sin_r
                uy = dx * sin_r + dy * cos_r
                if abs(ux) <= half_width and abs(uy) <= half_height:
                    if only_inside is None or self.bits[row + x] == only_inside:
                        self.bits[row + x] = value

    def paint(self, palette) -> bytes:
        """Маска в пиксели, с усреднением при уменьшении."""
        out = bytearray(SIZE * SIZE * 3)
        area = SS * SS
        for y in range(SIZE):
            for x in range(SIZE):
                r = g = b = 0
                for sy in range(SS):
                    row = (y * SS + sy) * W
                    for sx in range(SS):
                        colour = palette[self.bits[row + x * SS + sx]]
                        r += colour[0]
                        g += colour[1]
                        b += colour[2]
                offset = (y * SIZE + x) * 3
                out[offset] = r // area
                out[offset + 1] = g // area
                out[offset + 2] = b // area
        return bytes(out)


def write_png(path: Path, rgb: bytes):
    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)                                   # фильтр «никакой»
        raw += rgb[y * SIZE * 3:(y + 1) * SIZE * 3]

    def chunk(tag: bytes, body: bytes) -> bytes:
        return (struct.pack('>I', len(body)) + tag + body
                + struct.pack('>I', zlib.crc32(tag + body) & 0xFFFFFFFF))

    header = struct.pack('>IIBBBBB', SIZE, SIZE, 8, 2, 0, 0, 0)
    path.write_bytes(
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', header)
        + chunk(b'IDAT', zlib.compress(bytes(raw), 9))
        + chunk(b'IEND', b'')
    )


# 0 — бумага, 1 — чернила, 2 — охра ошейника, 3 — вырез глаза
PALETTE = {0: PAPER, 1: INK, 2: OCHRE, 3: PAPER}


def draw() -> Mask:
    """Пёс в профиль, смотрит вправо.

    Композиция с запасом от краёв: система кладёт иконку в скруглённый
    квадрат и подрезает углы. В первой раскладке грудь уходила за нижний
    край и выглядела обрезанной по ошибке.
    """
    mask = Mask()

    # Грудь и шея — снизу, чтобы голова легла поверх.
    mask.blob(440, 734, 238, 168, seed=6)

    # Голова.
    mask.blob(440, 384, 224, 208, seed=2)

    # Морда вытянута вправо и вниз: без неё силуэт читается медведем.
    mask.blob(676, 472, 178, 112, rotation=0.12, seed=3)
    mask.blob(650, 558, 124, 70, seed=9)

    # Нос.
    mask.blob(826, 454, 58, 50, seed=4)

    # Ошейник строго внутри силуэта. Единственное цветное пятно:
    # глаз ищет его первым, и по нему иконка узнаётся размером с ноготь.
    mask.band(470, 658, 248, 40, rotation=-0.1, only_inside=1, value=2)

    # Ухо кладётся последним и поверх ошейника: висячее ухо и правда
    # лежит поверх шеи. Пока оно было под ошейником, полоса перечёркивала
    # его насквозь и торчала влево посторонней палкой.
    mask.blob(272, 500, 90, 204, rotation=0.2, seed=5)

    # Глаз вырезан бумагой, а не поставлен точкой поверх.
    mask.blob(560, 348, 37, 39, seed=8, amount=0.05, value=3)

    return mask


if __name__ == '__main__':
    target = Path('Togo/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png')
    write_png(target, draw().paint(PALETTE))
    print(f'→ {target}')
