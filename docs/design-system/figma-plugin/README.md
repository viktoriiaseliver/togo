# Graphite → Figma

Плагин переносит дизайн-систему в ваш файл Figma (Togo). Запускается один раз; повторный запуск обновляет значения переменных и пересобирает страницы.

## Как запустить (Figma Desktop)

1. Скачайте папку `figma-plugin` и распакуйте.
2. Откройте файл Togo в **приложении Figma** (в браузере плагины из папки не запускаются).
3. Меню → **Plugins → Development → Import plugin from manifest…** → выберите `manifest.json`.
4. **Plugins → Development → Graphite → Figma**. Через 10–30 секунд внизу появится итог.

Шрифты до запуска: **SF Pro** (developer.apple.com/fonts) и **Material Symbols Rounded** (fonts.google.com/icons). Без них плагин подставит Inter и кружки вместо иконок и скажет об этом.

## Что создаётся

**Variables — 9 коллекций, 130 переменных, с алиасами:**

| Коллекция | Режимы | Что |
|---|---|---|
| Accent | Lime · Orange · Sky · Pink | сырые значения акцента, скрыты из публикации |
| Theme | Dark · Light · Dark HC · Light HC | `color/bg`, `fill`, `text`, `line`, `status`, `control`, `material`, `accent` → алиасы на Accent |
| Togo | — | `color/togo/*` → алиасы на Theme, `color/system/*` |
| Spacing | — | `space/0 … space/64`, шаг 4 |
| Layout | — | `layout/gap-cards`, `pad-card`, `margin-compact` … → алиасы на Spacing |
| Radius · Size · Type · Motion | — | радиусы, размеры касания, размеры шрифта, движение |

У каждой переменной: scopes (цвет текста предлагается только для текста, отступы — только для gap и padding и т. д.) и code syntax — Web `var(--fill-1)` и iOS `Color("fill.1")`.

**Стили:** 15 текстовых (iOS/Large Title … Caption 2, Numbers/XL … S; размер привязан к переменной), эффекты Elevation/1, Elevation/2 (светлая тема) и Glass/Blur 20.

**Страница Components** — наборы вариантов, все заливки, отступы и радиусы привязаны к переменным:
- Button — Variant (7) × Size (S, M, L, XL) × Content (Text, Icon + Text, Text + Icon, Icon) × State (Default, Pressed, Disabled), свойство Label;
- Toggle, SelectCircle, Badge, Chip, TextField, SegmentedControl, Avatar, SyncStatus;
- ListRow — Trailing (None, Value, Chevron, Toggle) × Subtitle;
- SectionHeader, Card (+ CardHeader и ActionRow на инстансах кнопок), InlineAlert, Toast, NavBar, TabBar, Alert.

**Страница Variables** — колонки всех цветов в каждом режиме Theme и сетка «акцент × тема» с живыми инстансами: переключите режим у фрейма — всё перекрасится.

**Страница Templates** — экран «Сегодня» из инстансов: 390 тёмная, 390 светлая, 320 тёмная (поля привязаны к `layout/margin-*`).

## Переключение темы и акцента в Figma

Выделите фрейм → панель справа → **Layer → Mode**: Theme (Dark / Light / HC) и Accent (Lime / Orange / Sky / Pink).

## Чего плагин не делает

- Специальные компоненты Togo (VerdictCard, Timeline, LabChart, SkillMatrix и др.) и полные шаблоны — слишком сложная разметка для ручной сборки в плагине. Их можно перенести слоями через плагин **html.to.design**: попросите меня — я выдам ссылку на страницу «Дизайн-система Togo» или шаблоны для импорта (ссылка живёт 10 минут).
- На тарифе Figma Starter у коллекции один режим: тогда Light и HC не создадутся, плагин об этом скажет.
- Тени в тёмной теме не нужны (там глубина — ступенью заливки), поэтому эффекты помечены «светлая».
