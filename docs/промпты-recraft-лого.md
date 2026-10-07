# Промпты Recraft для логотипа и иконки Togo

Снято 07.10.2026. Источник цвета — `DesignTokens/tokens.json`, не
`.claude/skills/togo-design/` (там палитра «Лёд» с `#1D4E89`,
это предложение, а не приложение — см. `ИСТОЧНИКИ.md` скилла).

## Что замерено до промптов

```
accent/light       #0E14A1      tokens.json:83    rgb 14, 20, 161
accent/dark        #A2C1FE      tokens.json:82    rgb 162, 193, 254
фон светлый        #ECEDF0      tokens.json:20    rgb 236, 237, 240
графит             #121211 → #262625               rgb 18,18,17 / 38,38,37
линия иллюстраций  stroke-width 2.5 (деталь 3.5), linecap round, viewBox 240×160
                   Togo/Resources/Иллюстрации-источник/*.svg, 8 файлов
```

Цвета в ТЗ совпадают с `tokens.json` до символа — сверено, расхождений нет.

**Иконка, которая стоит в сборке сейчас, — это ровно то, что ТЗ
запрещает.** `Togo/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`:
морда собаки силуэтом, графит на кремовом, ошейник терракотовый —
то есть «мультяшная морда» плюс статусный цвет в знаке. Это не довод
против ТЗ, а подтверждение, что менять есть что; и это же значит,
что сравнительная таблица этапа 1 должна включать нашу текущую иконку.

**Толщина линии иконки не равна толщине линии иллюстраций.** В пакете
2,5 на 240 — это ~1 % ширины; ТЗ требует ≥ 6 % при 1024. Рифма между
знаком и иллюстрациями идёт по форме (круглые торцы, один контур, одна
деталь акцентом), а не по весу штриха. Если требовать и то и другое
буквально, требования противоречат друг другу — выбрано требование ТЗ,
потому что оно про читаемость в 29 pt, а она измерима.

## Что Recraft умеет и чего не умеет для этой задачи

| | |
|---|---|
| Нативный SVG | `recraftv4_1_vector` / V4 Vector отдают настоящий вектор с путями, а не трассировку растра |
| Палитра | `controls.colors` — массив RGB (до 10, с весами) и `background_color`. Это НАДЁЖНЕЕ, чем hex в тексте промпта |
| Негативный промпт | в студии — кнопка настроек у поля промпта плюс тумблер «Avoid text in image» |
| Готовые вектор-стили | V3: `line_art`, `thin`, `bold_stroke`, `roundish_flat`, `marker_outline`, `cutout`, `emotional_flat` и ещё ~15 |
| Стиль `icon` | **только `recraftv2`** (`outline`, `pictogram`, `colored_outline`, …). У V3/V4 отдельного `icon` нет |
| Длина промпта | у API V3 — 1000 **байт**. Кириллица в UTF-8 это 2 байта на букву, то есть ~500 знаков против ~1000 латиницей. **Промпты писать по-английски**, иначе половина описания не влезет |

Оговорка об источнике: сторонние обёртки (Runware) пишут, что
**V4 и V4.1 Pro по API отвечают `400` на `style`, `style_id`
и `negative_prompt`**. Своей проверкой это не подтверждено — в
справочнике самого Recraft такого запрета я не нашёл. Если идти через
API на V4 — проверить одним запросом прежде, чем строить на этом
партию. В студии поля негативного промпта есть, и это другой путь.

**Чего Recraft не сделает, и это не настройка:**

- **не ответит, читается ли знак в 29 pt** — это замер на кадре,
  делается после;
- **не выдаст три варианта iOS 18 как комплект.** Светлая, тёмная
  и tinted — три отдельные генерации либо, вернее, одна отобранная
  форма, перекрашенная в Figma. Генерировать их по отдельности значит
  получить три разные формы под одним именем;
- **буквы врёт.** Словесный знак обязан рифмоваться с SF Pro Rounded
  300 — это проверяемое требование, и генератор его не держит.
  Recraft здесь годится **на эскиз направления**, финальный знак
  рисуется в Figma поверх SF Pro Rounded. Промпты направления 3 ниже
  даны для этапа 1 (выбор идеи), а не для сдачи.

## Общие настройки на все промпты

```
модель      Recraft V4.1 Vector (в студии — Vector art)
размер      1024×1024 для иконки; для словесного знака — широкий
            формат из панели размеров (≈2:1)
негативный  (см. у каждого; общий хвост одинаков)
Avoid text in image  ВКЛ везде, кроме 1A, 1B и направления 3
```

Общий хвост негативного промпта — повторять в каждом:

```
gradient, drop shadow, inner shadow, glow, bevel, emboss, 3d, glossy,
highlight, texture, noise, grain, photo, realistic, perspective,
background pattern, rounded square frame, app icon frame, border,
dog face, muzzle, snout, eyes, cartoon animal, puppy, bowl, kennel,
doghouse, leash, heart, star, watermark, signature,
orange, amber, terracotta, red, green, purple, multicolor
```

Запрет оранжевого, янтаря и терракоты стоит здесь не из вкуса:
это статусные цвета системы (запас, окно натощак, тревога), и в знаке
они означали бы то, чего знак не означает.

### Нулевой прогон — проверка инструмента, а не идеи

Прежде чем судить партию, одна генерация на заведомо простой форме:
круг с одной прорезью, палитра выставлена через `controls.colors`
двумя цветами. **Смотреть не на красоту, а на то, попали ли цвета
в картинку.** Если палитра не применилась, все дальнейшие выводы
о «неподходящем цвете» будут про инструмент, а не про эскизы.

---

# Этап 1 — три направления, чёрно-белое

Чёрно-белое здесь не стилистика, а условие отбора: форма, которая
держится без цвета, доживёт до tinted. Палитра на этом этапе —
`rgb 0,0,0` и фон `rgb 255,255,255`, без исключений.

## Направление 1 — жетон (предпочтительное)

### 1A · контурный жетон с буквой

```
Flat vector app icon mark: a single dog ID tag seen straight on —
a soft rounded shape hanging from one small open jump ring at the top.
Inside the tag body, one lowercase letter "t" in a geometric rounded
sans-serif, centered, light weight, round terminals.
Construction: pure outline, one uniform very thick stroke weight
(about one sixteenth of the icon width), round line caps and joins,
no fill, no second line weight.
Strict two tones: pure black lines on a flat white background.
Perfectly centered, symmetrical, generous even margin on all sides,
one closed silhouette, readable when scaled down to 16 pixels.
Flat 2D, no gradient, no shadow, no texture, no perspective.
```

Негативный: общий хвост **минус** `watermark`-соседи по буквам, плюс
`words, sentences, numbers, multiple letters, serif, italic, script,
handwriting`. Тумблер «Avoid text in image» — **выключен**: буква нужна.

Ожидаемая болезнь: модель приделает собаке морду на жетон или сделает
кольцо замкнутым сверху так, что в 29 pt оно слипнется с телом.
Второе лечится в промпте словом `wide gap between the ring and the tag body`.

### 1B · заливка, буква вырезана

```
Flat vector app icon mark: a solid filled dog ID tag shape, straight on,
with a small circular hole punched near the top where a jump ring passes.
A lowercase letter "t" is knocked out of the solid shape in negative
space, centered, geometric rounded sans-serif, light weight.
Construction: one solid silhouette, no outline, no stroke, counters and
the knocked-out letter are the only white areas; every negative gap is
wide and open.
Strict two tones: pure black shape on a flat white background.
Centered, symmetrical, generous margin, readable at 16 pixels.
Flat 2D, no gradient, no shadow, no texture.
```

Негативный: как 1A. «Avoid text in image» — выключен.

Это тот вариант, из которого tinted получается даром: силуэт уже
единый, остаётся вынуть фон.

## Направление 2 — косточка-показание

Главный риск направления — что знак прочтут как еду. В промпте
про это сказано прямо, и в приёмке это первый вопрос к посторонним
глазам, а не к нам.

### 2A · полоса с утолщениями, частично заполненная

```
Flat vector icon mark: a short horizontal bar with two thickened
rounded ends — a dog bone silhouette reduced to a minimal gauge.
The bar reads as a progress meter for remaining time, not as food:
the left portion is a solid filled segment, the right portion is an
empty outline of the same shape, so the mark reads as partly filled.
Construction: geometric, strictly horizontal, bilaterally symmetrical
ends, one uniform very thick stroke weight (about one sixteenth of the
icon width), round line caps.
Strict two tones: pure black on a flat white background.
Centered in a square, generous margin above and below, readable at
16 pixels.
Flat 2D, no gradient, no shadow, no texture, no perspective.
```

Негативный: общий хвост плюс `food, meat, chewing, dog treat, teeth,
bite marks, cartoon bone with shine`.

### 2B · то же, но вертикальная отсечка вместо заливки

```
Flat vector icon mark: a short horizontal capsule bar with two
thickened rounded ends, outlined only. One short vertical tick crosses
the bar left of center, marking a position along it, like a gauge
reading. No fill inside the bar.
Construction: geometric, strictly horizontal, symmetrical ends, one
uniform very thick stroke weight, round line caps and joins, wide open
interior.
Strict two tones: pure black on a flat white background.
Centered in a square, generous margin, readable at 16 pixels.
Flat 2D, no gradient, no shadow, no texture.
```

Негативный: как 2A.

## Направление 3 — словесный знак

Напоминание из раздела выше: это эскиз направления, не финал. Буквы
Recraft ставит нестабильно, а требование «рифмуется с SF Pro Rounded
300» проверяется наложением на настоящий шрифт.

### 3A · «togo», последняя «o» — кольцо жетона

```
Lowercase wordmark reading "togo" — four letters: t, o, g, o.
Typeface character: geometric rounded sans-serif, light weight, thin
uniform strokes, round terminals, wide circular counters, single-storey
"g" with a short straight descender, even tight letter spacing,
all letters sitting on one baseline.
The final letter "o" is drawn as a dog ID tag ring: a perfect circle of
the same stroke weight with a small open jump ring attached at its top,
so the word ends in a hanging tag.
Horizontal lockup, strict two tones: pure black letters on a flat white
background, generous even margin.
Flat 2D vector, no gradient, no shadow, no texture, no outline box.
```

Негативный: общий хвост плюс `serif, slab, italic, script, handwriting,
bold, condensed, extra letters, misspelling, tagline, additional words,
underline`. «Avoid text in image» — **выключен**.

### 3B · «togo», последняя «o» — след

```
Lowercase wordmark reading "togo" — four letters: t, o, g, o.
Typeface character: geometric rounded sans-serif, light weight, thin
uniform strokes, round terminals, wide circular counters, single-storey
"g", even tight letter spacing, one baseline.
The final letter "o" is replaced by a simple dog paw trace: one rounded
pad shape with three small separate toe dots arranged above it, built
from the same thin stroke weight, occupying exactly the width and height
of the other letters.
Horizontal lockup, strict two tones: pure black on a flat white
background, generous even margin.
Flat 2D vector, no gradient, no shadow, no texture.
```

Негативный: как 3A, плюс `four toes, realistic paw, fur`.

### 3C · знак в строку (после выбора иконки)

Делать **только** когда направление выбрано: промпт должен описывать
уже выбранную форму, иначе в строке окажется другая иконка, чем
в квадрате, и расхождение заметят поздно.

```
Horizontal logo lockup: on the left, <ОПИСАНИЕ ВЫБРАННОГО ЗНАКА
ОДНИМ ПРЕДЛОЖЕНИЕМ>; to its right, the lowercase wordmark "togo" in a
geometric rounded sans-serif, light weight, thin uniform strokes, round
terminals, single-storey "g".
The mark height equals the cap height plus ascender of the wordmark;
the gap between mark and word equals the width of one letter "o".
Both share one stroke weight and one optical baseline.
Strict two tones: pure black on a flat white background, generous even
margin, nothing else in the frame.
Flat 2D vector, no gradient, no shadow, no texture.
```

---

# Этап 2 — цвет на выбранной форме

Форма одна и та же; меняется только палитра. Если на этом шаге форма
«чуть поехала» — это не вариант темы, это другая иконка, и её надо
вернуть к выбранной в Figma, а не принять.

Палитру задавать **контролем, а не словами**. Hex в тексте промпта
оставить тоже — он иногда работает, — но решает `controls.colors`.

| Вариант | `controls.colors` | `background_color` | хвост промпта |
|---|---|---|---|
| Светлая | `[{rgb:[14,20,161]}]` | `[236,237,240]` | `deep indigo mark on a flat pale cool grey background` |
| Тёмная | `[{rgb:[162,193,254]}]` | `[18,18,17]` | `pale periwinkle blue mark on a flat near-black graphite background` |
| Tinted | `[{rgb:[0,0,0]}]` | `[255,255,255]` | `pure black solid silhouette on pure white, no grey, no halftone` |

Tinted в Recraft делается **чёрным по белому**, а не «прозрачным»:
прозрачность он не рисует. Прозрачный фон получают в Figma, выбив
белое; поэтому в промпте tinted стоит `no grey` — любой серый пиксель
после выбивания даст рваный край.

Хвост палитры дописывается к выбранному промпту этапа 1 **вместо**
строки `Strict two tones: pure black … white background`, остальное
слово в слово. Переписывать промпт заново нельзя: перенабор меняет
форму молча.

---

## Приёмка — что считается годным результатом

Генерация не принимается глазами на экране 1024. Проверяется так:

1. **Размер.** Уменьшить PNG до 87 px (29 pt @3x) и 120 px (40 pt @3x)
   и посмотреть на них, а не на оригинал. Слиплось кольцо с телом,
   закрылась внутренность буквы — брак.
2. **Толщина.** Самая тонкая линия при 1024 — не меньше 61 px (6 %).
   Меряется пипеткой на кадре, не оценивается.
3. **Цвет.** Пипеткой в трёх точках: заливка, фон, деталь. Сверить
   с таблицей выше **числом**. Расхождение в один шаг — это не
   «близко», это другой цвет: `#0E14A1` в системе один.
4. **Tinted.** Выбить белое и посмотреть силуэт на двух подложках —
   светлой и тёмной. Если знак держался только за счёт фона, здесь
   он развалится, и это нормальный исход отбора.
5. **Домашний экран.** Положить рядом с чужими иконками на реальном
   устройстве, светлая и тёмная тема. Это единственный пункт, который
   не заменяется ничем.
6. **Чужие глаза на направление 2.** Один вопрос без подсказки:
   «что это?». Ответ «кость, еда» — направление не сработало,
   и это ответ, а не повод переписывать промпт.

**SVG от Recraft — не финальный файл.** Пути приходят с лишними
узлами, кривые не выровнены по сетке. Отобранная форма перерисовывается
в Figma и сдаётся оттуда — иначе в гайд уедет геометрия, которую никто
не контролирует.

## Источники

- [Recraft · Practical Prompt Engineering: a V4 Guide](https://www.recraft.ai/blog/prompt-engineering-guide)
  — структура промпта для вектора и логотипов, правило «короткий промпт
  — модель придумывает, длинный — исполняет»
- [Recraft · How to Generate a Logo Using Recraft](https://www.recraft.ai/blog/how-to-generate-a-logo-using-ai)
- [Recraft · Negative prompts](https://www.recraft.ai/docs/recraft-studio/image-generation/working-with-text-and-prompts/negative-prompts)
  — не писать «no apples», писать «apples»; тумблер «Avoid text in image»
- [Recraft · Styles (API reference)](https://www.recraft.ai/docs/api-reference/styles)
  — стиль `icon` только у V2; у V3 Vector 25 стилей
- [Recraft · API docs](https://www.recraft.ai/docs) — имена моделей
  `recraftv4_1_vector`, `recraftv4_1`, `recraftv3`, `recraftv2`
- [Runware · Controlling output colors with palettes and backgrounds (V4.1)](https://runware.ai/docs/models/recraft-v4-1/guides/color-palettes)
  — `controls.colors` до 10 цветов с весами; **оттуда же непроверенное
  утверждение про `400` на `negative_prompt` у V4**
- [ComfyUI · Recraft Text to Vector](https://docs.comfy.org/built-in-nodes/partner-node/image/recraft/recraft-text-to-vector),
  [fal.ai · Recraft V3 text-to-image](https://fal.ai/models/fal-ai/recraft/v3/text-to-image/api)
  — перечни substyle `vector_illustration`
