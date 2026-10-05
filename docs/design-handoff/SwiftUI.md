# Graphite → SwiftUI

Как перенести токены и компоненты в код. Имена совпадают с Figma Variables (`tokens/figma-variables.json`).

## Цвета → Asset Catalog

Одна Color Set на переменную коллекции **Theme**. Имя ассета = имя в Figma без `color/`, «/» → «.»: `color/fill/1` → `fill.1`.

| Figma | CSS | Asset | Варианты |
|---|---|---|---|
| color/bg/page | --page | bg.page | Any, Dark, High Contrast ×2 |
| color/bg/primary | --bg-primary | bg.primary | |
| color/fill/1 · 2 · 3 | --fill-1 · 2 · 3 | fill.1 · 2 · 3 | |
| color/text/primary · secondary · disabled | --text-* | text.* | |
| color/line/separator | --separator | line.separator | |
| color/status/error · warning (+ -subtle) | --status-*, --*-subtle | status.* | |
| color/accent/fill · pressed · text · on · subtle · subtle-text · knob | --accent* | accent.* | Any (light), Dark, HC |

Доступ: `Color("fill.1")`, либо сгенерированный `Color.fill1` (Xcode 15+ создаёт символы ассетов автоматически).

**Акцент.** Коллекция Accent (Lime · Orange · Sky · Pink) → по одной папке ассетов на акцент или один набор, если акцент у приложения один. Системный `AccentColor` = `accent.fill`; `.tint(Color("accent.fill"))` на корне.

**Стекло** — не цвет, а материал: `.background(.regularMaterial)`; при Reduce Transparency система сама подставит непрозрачный фон.

## Отступы, радиусы, размеры

```swift
enum Space { static let s4: CGFloat = 4, s8 = 8, s12 = 12, s16 = 16, s20 = 20, s24 = 24, s28 = 28, s32 = 32, s40 = 40, s48 = 48, s64 = 64 }
enum Layout { static let gapCards = Space.s8, gapSections = Space.s32, padCard = Space.s20, padRow = Space.s16, padRowY = Space.s12 }
enum Radius { static let sheet: CGFloat = 36, card = 28, row = 24, inner = 16 }
enum Size { static let hit: CGFloat = 44, button = 52, buttonXL = 64, row = 64 }
```

Только шаг 4. Поля экрана — `.contentMargins(.horizontal, sizeClass == .compact && width < 375 ? 16 : 20)`. Скругления — `RoundedRectangle(cornerRadius: Radius.card, style: .continuous)`; пилюля — `Capsule()`.

Отступы, которые должны расти с текстом: `@ScaledMetric(relativeTo: .body) var pad = Layout.padCard`.

## Типографика

| Figma | SwiftUI |
|---|---|
| type/size/large-title … caption-2 | `.font(.largeTitle)` … `.font(.caption2)` — только системные стили |
| headline | `.font(.headline)` (600) |
| number-xl · l · m | `.font(.system(size: 80/56/44, weight: .light, design: .rounded))` + `.dynamicTypeSize(...DynamicTypeSize.accessibility1)` (потолок ≈150 %) + `.monospacedDigit()` |

Минимум 12 pt: `caption2` на размере L = 11, поэтому подписи — `.caption` (12), не `.caption2`.

## Движение и хаптика

- Нажатие: `ButtonStyle` с `.scaleEffect(isPressed ? 0.96 : 1)` и `.animation(.snappy(duration: 0.15))`.
- Переходы: `.animation(.snappy)`; цифры: `.contentTransition(.numericText())`.
- Reduce Motion: `@Environment(\.accessibilityReduceMotion)` → только `.opacity`.
- Хаптика: `.sensoryFeedback(.selection, trigger:)` — тумблер, сегмент; `.impact(weight: .light)` — порог свайпа; `.warning` — удаление; `.success` — готово.

## Компоненты

| Graphite | SwiftUI |
|---|---|
| Button (primary · secondary · tinted · destructive · plain) | `Button` + свой `ButtonStyle` (`GraphiteButtonStyle(variant:size:)`); только иконка — `Label(...).labelStyle(.iconOnly)` + `.accessibilityLabel` |
| Toggle | `Toggle(...).tint(Color("accent.fill"))` |
| SelectCircle | `Image(systemName: on ? "checkmark.circle.fill" : "circle")` |
| TextField · TextArea | `TextField`, `TextField(axis: .vertical)` с `.lineLimit(3...)` |
| Menu | `Picker(...).pickerStyle(.menu)` |
| Slider | `Slider(value:in:step:)` |
| SegmentedControl | `Picker(...).pickerStyle(.segmented)` |
| ChoiceChips | `HStack` во `ViewThatFits` / свой `Layout` с переносом |
| ActionRow | `ViewThatFits { HStack { … } ; VStack { … } }` |
| Card · CardHeader | `VStack(alignment: .leading, spacing: 12)` + `.padding(Layout.padCard)` + `.background(Color("fill.1"), in: .rect(cornerRadius: Radius.card))` |
| ListRow | строка `List` с `.listRowBackground` или свой `HStack`; хвост — `ViewThatFits` |
| SectionHeader | `Section(header:)` |
| NavBar · FitHeader | `.navigationTitle` + `.toolbar`; на AX-размерах заголовок `.navigationBarTitleDisplayMode(.large)` |
| TabBar | `TabView` |
| Sheet | `.sheet` + `.presentationDetents([.medium, .large])` + `.presentationCornerRadius(36)` |
| Alert · ContextMenu | `.alert`, `.contextMenu` |
| Toast с «Отменить» | оверлей + `Task.sleep(5 s)`; удаление — после истечения |
| Calendar | `DatePicker(..., displayedComponents: .date).datePickerStyle(.graphical)` или свой `LazyVGrid` для отметок |
| TimeField | `DatePicker(.hourAndMinute)` + быстрые кнопки |
| Timeline · WeekChart · LabChart | `Swift Charts`: `LineMark`, `PointMark`, `RectangleMark` (норма), `BarMark` |
| Avatar | `Circle()` + `Text(initials)` / `Image` |
| ListSkeleton | `.redacted(reason: .placeholder)` |
| RefreshIndicator | `.refreshable` |
| WidgetPreview · LiveActivity | WidgetKit, ActivityKit + `AppIntent` для «Вывожу» |
| PushNotification | `UNNotificationCategory` с действиями; доза — `.timeSensitive` |

## Доступность

- Каждая кнопка-иконка — `.accessibilityLabel`.
- Статус словом, не только цветом (`.accessibilityValue("вне нормы")`).
- Цели касания от 44: `.frame(minWidth: 44, minHeight: 44)` + `.contentShape(.rect)`.
- Проверка: Xcode Previews с `.dynamicTypeSize(.accessibility1)` на iPhone SE (320 pt), светлая и тёмная, Increase Contrast.
