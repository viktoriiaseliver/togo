# Подготовка кода под Figma

Замер 23.09.2026. Задача — не «сделать красиво», а свести код к тому,
что можно связать с компонентом в Figma: один View с параметрами
против нескольких похожих, и ни одного числа там, где должен стоять
токен.

Дизайн здесь не меняется. Всё, что ниже, — опись и решения, которые
нужно принять до правок, а не по ходу.

## 1. Таблица соответствия: код ↔ Figma

Имя в Figma уже записано в док-комментарии компонента (`/// Figma: …`)
— это и есть источник; таблица ниже собрана из кода, а не из памяти.

| Компонент в коде | Имя в Figma | Где |
|---|---|---|
| `TGBanner` | `Banner` | `Togo/DesignSystem/Components/TGBanner.swift:7` |
| `TGButton` | `Button` | `TGButton.swift:8` |
| `TGStepButton` | `StepButton` | `TGButton.swift:132` |
| `TGStepper` | `Stepper` | `TGButton.swift:150` |
| `TGChip` | `Chip` | `TGChip.swift:4` |
| `TGChipGroup` | `ChipGroup` | `TGChip.swift:68` |
| `TGCloseButton` | `CloseButton` | `TGCloseButton.swift:10` |
| `TGIconRow` | `IconRow` | `TGIconRow.swift:11` |
| `TGLink` | `NavigationRow` | `TGLink.swift:10` |
| `TGLoading` | `Loading` | `TGLoading.swift:8` |
| `TGSectionHeader` | `SectionHeader` | `TGRows.swift:4` |
| `TGExplainer` | `Explainer` | `TGRows.swift:28` |
| `TGListRow` | `ListRow` | `TGRows.swift:40` |
| `TGStat` | `Stat` | `TGRows.swift:121` |
| `TGAvatar` | `Avatar` | `TGRows.swift:145` |
| `TGSheetHandle` | `SheetHandle` | `TGScaffolds.swift:4` |
| `TGSheet` | `Sheet` | `TGScaffolds.swift:22` |
| `TGScreen` | `Screen` | `TGScaffolds.swift:125` |
| `TGDivider` | `Divider` | `TGSurfaces.swift:6` |
| `TGCard` | `Card` | `TGSurfaces.swift:24` |
| `TGTile` | `Tile` | `TGSurfaces.swift:53` |

**Имени в Figma нет у пяти компонентов** — их надо либо назвать, либо
признать не-компонентами:

| Компонент | Где | Что это |
|---|---|---|
| `TGCheckRow` | `TGCheckRow.swift:14` | ряд плана дня с отметкой; просится в `ListRow` вариантом |
| `EmptyStateCard` | `TGLoading.swift:30` | пустое состояние; вариант `Card` |
| `TGStateful` | `TGLoading.swift:56` | не компонент, а переключатель трёх состояний — в Figma ему соответствия нет и не нужно |
| `TGStopwatch` | `TGStopwatch.swift:12` | секундомер прогулки |
| `ComponentGallery` | `ComponentGallery.swift:9` | витрина компонентов для глаз, в сборку витрины не идёт |

## 2. Опись дублей: что резать, решает Виктория

В Figma это варианты одного компонента, а связать можно только один
View. Ниже — семьи похожих, собранные по коду. **Резать не на ходу.**

### Ряды — 12 своих против трёх общих

Общие: `TGListRow`, `TGCheckRow`, `TGIconRow`.
Свои: `CareTaskRow` (`CareScreen`), `ConflictRow` и `MemberRow`
(`FamilyScreen`), `DocumentRow` (`DocumentPhotos`), `DogRow`
(`DogSwitcher`), `FAQRow` (`DataPrivacyScreen`), `InterruptRow`
(`OnboardingSteps`), `ProtocolRow` (`HealthScreen`), `StockRow`
(`FoodStockScreen`), `TimePickerRow` (`ScheduleEditor`), `TimelineRow`
и `TimelineMarkRow` (`DayTimeline`).

Вопрос к решению: какие из двенадцати — варианты `ListRow`, а какие
самостоятельные. Кандидаты в варианты: `FAQRow`, `ProtocolRow`,
`InterruptRow`, `DocumentRow` — у всех форма «подпись слева, значение
справа». Кандидаты в самостоятельные: `TimelineRow` и `TimelineMarkRow`
(у них своя геометрия ленты), `TimePickerRow` (внутри системный
пикер).

### Карточки — 7 своих против `TGCard`

`ActiveSessionCard`, `AskSignalCard`, `DayOutCard`,
`DocumentPhotosCard`, `MedicationCard`, `MergeConflictCard`,
`PackingListCard`.

Все семь используют `TGCard` внутри — то есть это не дубли
контейнера, а содержимое. В Figma им соответствуют не варианты
`Card`, а отдельные блоки. **Резать нечего**, и это стоит записать,
чтобы не резали.

> **Восьмой была `WalkRhythmCard`, и её снесли 23.10.2026** — редизайн
> «Кино» заменил её на `КиноМетрика` в «Истории» (кадр 10) и на блок
> вердикта в шторке «Просится» (кадр 07). Правка этой строки — не
> уборка: **список читает дизайнер**, и по нему он завёл бы в Фигме
> блок, которого в приложении нет. Тот же класс, что у
> `Token.FontSize.micro`: ноль вызовов в Swift не значит ноль
> читателей, пока предмет уезжает в макет.

### Шторки — 30 штук

Все тридцать строятся на `TGSheet`. Дублей нет: это разное
содержимое в одном контейнере. Тот же вывод, что и с карточками.

## 3. Литералы оформления: опись

Считано по `Togo/DesignSystem` и `Togo/Features`, строки с `Token.`
не в счёт.

| Что | Сколько | Где гуще всего |
|---|---|---|
| Цвет | **0** | — |
| Тень | **0** | — |
| Кегль (`.font(.system(size:))`) | 36 | `WalkMode` ×4, `ActionGrid` ×4, `DayPlan` ×3 |
| Отступ и интервал | 106 | `DayTimeline` ×8, `LogSheets` ×7, `ActionGrid` ×7 |
| Радиус | 3 | `FeedingScreen`, `VetSummaryScreen`, `HistoryScreen` |
| Размер (`.frame(width:/height:)`) | 36 | `EmergencyScreen` ×4, `WalkMode` ×4, `TripScreens` ×3 |

**Цвет и тень уже целиком на токенах** — это лучшая новость описи:
самое дорогое для Figma место чинить не надо.

Кегли и размеры — настоящий долг: 36 и 36. Отступы (106) надо читать
осторожно, в них попадают `spacing: 0` и `padding(0)`, где токен
не нужен.

**Правило на правку:** нет токена — завести токен в
`DesignTokens/tokens.json`, а не подставить число. Генератор
`make tokens` и `make tokens-check` уже держат это.

## 4. Сторож

`TogoTests/DesignLiteralTests.swift`:

- цвет в слое вида — **ноль, строго**: сегодня их нет, и сторож
  не даёт появиться первому;
- тень — ноль, строго;
- кегль, радиус, размер — долг по числу, только вниз.

Сторож показан красным подделкой: литеральный цвет в `TGCard` роняет
прогон.

## Чего этот документ не решает

Связывание (Code Connect) не заведено: файлов `.figma.ts` в проекте
нет, и до решения по дублям заводить их рано — связывать надо то, что
останется, а не то, что сегодня.
