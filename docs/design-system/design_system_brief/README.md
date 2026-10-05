# Brief для дизайн-системы Togo: новый главный экран и iOS 26

Кому: тому, кто ведёт дизайн-систему (компоненты в `components/`, токены в `tokens/`, плагин в `figma-plugin/`).
Визуальная спецификация: `Togo Дизайн-система - дополнение.dc.html`. Экраны продукта: `Togo Экраны.dc.html`. Утверждённый концепт: `Togo Главный экран - разбор.dc.html`.

## Правила, которые не меняются

- Цвета и шрифт — только токены Togo. Lime — акцент. Янтарь — только окно натощак (и плитка «Срыв»). Терракот — только инцидент и тревога.
- Кнопки — пилюли (`--radius-pill`). Крупные цифры — SF Pro Rounded 300 (`--fw-number`). Иконки — Material Symbols Rounded, weight 300.
- Минимальный размер текста — 12. Минимальная зона касания — 44.

## Новые токены

| Токен | Dark | Light | Зачем |
|---|---|---|---|
| `--accent-edge` | #A9C74A | #7AA81A | грань главной кнопки (`--accent-pressed` слишком близок к акценту) |
| `--error-edge` | #B8503F | #8E1109 | грань «Позвонить врачу» |
| `--fill-edge` | = `--fill-3` | = `--fill-3` | грань второстепенных кнопок |
| `--edge-height` | 4 (xl), 3 (l) | — | высота грани |
| `--glass-regular` | rgba(40,40,40,.55) | rgba(255,255,255,.58) | заменяет `--glass` |
| `--glass-clear` | rgba(255,255,255,.10) | rgba(255,255,255,.35) | кнопки на стекле |
| `--glass-tint-accent` | rgba(212,247,95,.18) | rgba(156,212,37,.22) | активная вкладка, действие в строке |
| `--glass-shadow` | inset 0 1px 0 rgba(255,255,255,.14), 0 0 0 1px rgba(255,255,255,.08), 0 8px 32px rgba(0,0,0,.35) | inset 0 1px 0 rgba(255,255,255,.9), 0 0 0 1px rgba(16,16,28,.06), 0 8px 32px rgba(16,16,28,.12) | блик, контур и тень стекла |
| `--blur-glass` | 24 (было 20) + saturate 180% | — | |
| `--radius-sheet-floating` | 44 | — | шторка iOS 26 на средней высоте |
| `--fs-number-hero` | 96 (iPhone), 112 (iPad), 80 (разворот) | — | показание на главном |

Добавить в `tokens.dtcg.json`, `figma-variables.json` и CSS. Режимы HC: стекло становится непрозрачным `--fill-1`/`--fill-2`.

## Изменить существующие

1. **Button** — prop `edge?: boolean`. Тень `0 var(--edge-height) 0` цвета грани по варианту: primary → accent-edge, secondary/surface → fill-edge, destructive-filled → error-edge. Нажатие: грань 0, `translateY(var(--edge-height))`, без scale. Disabled — без грани.
2. **InlineAlert → StatusLine** — tone `neutral` (fill-sunken / text-secondary); prop `action {label, onPress}` — пилюля 36 справа с подложкой `glass-tint-accent` (или прозрачная для warn/err); одна строка, при AX-размерах до 2 строк. VoiceOver: действие — отдельный элемент ротора.
3. **ChoiceChips** — prop `other` (значение + onChange): последний чип «Другое…» с обводкой accent-text и иконкой edit; раскрывает поле (TextField, радиус row, обводка 2 accent) под чипами. Свой вариант после 2 использований — обычный чип с иконкой person.
4. **TabBar** — материал glass-regular + glass-shadow; активная вкладка — glass-tint-accent; prop `compact` (только иконки, 48) для разворота; вариант `top` для iPad (капсула по центру сверху, + кнопка боковой панели).
5. **Sheet** — detent `medium`: отступ 8 со всех сторон, радиус 44, glass-regular; detent `large`: радиус 36, пристыковка, непрозрачная `--fill-1`. Кнопка закрытия — круг 44 glass-clear.
6. **Toast** — вариант `choices` (строка из 4 чипов, «Как сходил?»).
7. **WalkBar** — перевести на каркас: HeroReading(timer) + FactList(«отмечено») + Button edge; в режиме поведения второй слот — «Срыв» (warning-subtle / status-warning, грань status-warning).
8. **PushNotification** — материал glass-regular, действия — пилюли glass-clear; тип «доза на улице».
9. **LiveActivity** — добавить представления Dynamic Island: compact (иконка + таймер), minimal (кружок), expanded (таймер + 2 кнопки + строка дозы). Натощак — янтарный compact.
10. **WidgetPreview** — small: HeroReading + главная кнопка по режиму туалета; второй small — натощак.
11. **DogSwitcher** — компактный вид 40 и стопка аватаров при 2+ собаках.
12. **OnboardingStep** — 3 шага, прогресс из трёх сегментов.

## Новые компоненты

| Компонент | Props | Варианты и состояния |
|---|---|---|
| `HeroReading` | label, value, sub, variant: default \| night \| empty \| timer, size: phone \| pad \| landscape | ночь — text-secondary; пусто — «—»; таймер — accent-text. VoiceOver — один элемент «Гулял 2 часа 10 минут назад» |
| `FactList` | items[{time, what, who, pending}], onPress | строки 52, разделитель с отступом 16; pending — иконка cloud_off и «не отправлено» |
| `RecordTile` | icon, title, sub, onPress | 64, радиус row, иконка в круге 40 fill-2 |
| `IncidentTile` | sub, onPress | error-subtle / status-error, первым в шторке |
| `StockMeter` | name, left, unit, perDay, until, pct, onBought | число Rounded 56; полоса всегда accent — срочность передаёт StatusLine |
| `DayScale` | events[{start, end, kind}], now | виды: outside, dose, fasting, incident, plan; стрелка «сейчас» |
| `ReadOnlyBar` | icon, text | пилюля 64 с контуром separator |
| `TodayLayout` (шаблон) | state | 10 состояний из `Togo Экраны`, раздел 1 |
| `TodayLandscape` (шаблон) | state | 2 колонки: информация · действия; отступ 62 со стороны острова |
| `TodayPad` (шаблон) | state | 3 колонки 380 · 1fr · 320; таб-бар сверху |

## Обязательные правила (проверка пройдена)

- У каждой кнопки — иконка Material Symbols Rounded 300 слева от подписи; иконка-кнопка без подписи — только круг 44 (настройки, закрыть).
- Любая зона касания ≥ 44 × 44, включая действие внутри StatusLine (44), кнопки уведомлений (44), иконки таб-бара (48–56).
- На экране одна залитая акцентом кнопка. Tint — только активная вкладка и действие в строке. Янтарь — только натощак и «Срыв».
- iPhone SE 375 × 667: показание 80, поля 16, компактный таб-бар 56; при AX3 «сегодня» = 1 строка, второстепенные в столбик, главная кнопка всегда видна без прокрутки.
- Текст ≥ 12, контраст текста ≥ 4.5 : 1, «Уменьшить прозрачность» → стекло становится fill-1.

## Открытый вопрос

1. Плитка «Срыв» янтарём — подтвердить, что это последнее исключение из правила.

## Приёмка

- Все экраны `Togo Экраны.dc.html` собираются только из компонентов системы, без локальных стилей.
- Каждый компонент — Dark, Light, Dark HC, Light HC; «Уменьшить прозрачность» превращает стекло в непрозрачную заливку.
- Карточка в `*.card.html` по образцу соседних, `.prompt.md` с примером, `.d.ts` с типами.
- Плагин Figma: новые переменные, Button с `Edge` (Drop shadow Y 4, Blur 0), стекло — эффект Glass или Background blur 24, новые компоненты на странице Components, шаблоны iPhone SE 375, iPhone 402, iPhone landscape 874, iPad 1194.
