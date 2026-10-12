# Code Connect · Того

Эти файлы связывают компоненты Figma с кодом: открыв компонент в Dev Mode,
разработчик видит настоящий вызов SwiftUI, а не описание.

Файлы намеренно **не входят** в таргет приложения — их собирает CLI Figma
вместе с пакетом `figma-swift`. Так приложение остаётся без сторонних
зависимостей и собирается на чистой машине без токена Figma.

## Как подключить

1. Создать библиотеку в Figma и вставить её ключ в `Figma/figma.config.json`
   вместо `REPLACE_WITH_FILE_KEY`.
2. В каждом `.figma.swift` заменить `NODE_ID` на id соответствующего
   компонента (правая кнопка на компоненте → Copy link to selection).
3. Установить CLI и опубликовать:

   ```sh
   npm install -g @figma/code-connect
   figma connect publish --token "$FIGMA_TOKEN" --config Figma/figma.config.json
   ```

## Правило соответствия

| Figma            | Swift            | Свойства компонента                     |
|------------------|------------------|-----------------------------------------|
| `Button`         | `TGButton`       | variant, size, systemImage, disabled    |
| `Chip`           | `TGChip`         | label, sublabel, selected, tone         |
| `ChipGroup`      | `TGChipGroup`    | items                                   |
| `Card`           | `TGCard`         | surface, padding, elevated              |
| `Tile`           | `TGTile`         | selected, tone                          |
| `Banner`         | `TGBanner`       | tone, title, subtitle, systemImage      |
| `ListRow`        | `TGListRow`      | title, value, systemImage, accessory    |
| `Stat`           | `TGStat`         | value, caption                          |
| `Avatar`         | `TGAvatar`       | initial, image, size, tint              |
| `SyncMark`       | `TGSyncMark`     | author, synced                          |
| `Stepper`        | `TGStepper`      | value, unit, step                       |
| `SectionHeader`  | `TGSectionHeader`| title, subtitle                         |
| `Explainer`      | `TGExplainer`    | text                                    |
| `Divider`        | `TGDivider`      | inset                                   |
| `Sheet`          | `TGSheet`        | title, subtitle, content, footer        |
| `Screen`         | `TGScreen`       | title, content, bottom                  |

Значения (цвета, отступы, радиусы) в обе стороны идут из
`DesignTokens/tokens.json`: в Figma — как переменные, в Swift — как `Token.*`.
