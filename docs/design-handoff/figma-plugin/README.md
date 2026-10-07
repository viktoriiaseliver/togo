# Graphite → Figma · v4 (окт 2026)

Плагин собирает в файле Figma всю систему и всё приложение: переменные, стили, компоненты и 67 экранов чистовика (`Togo ФИНАЛ` + `Togo ФИНАЛ v2`). Повторный запуск обновляет переменные и пересобирает страницы Components, Variables, Togo · компоненты, Togo · смелее, Templates, Togo · экраны-компоненты, Screens · все экраны (ручные правки на этих страницах пропадут — держите свои макеты на других страницах).

## Что нового в v4

- **Screens · все экраны** — 67 экранов в 21 разделе: онбординг, профиль, режимы, семья, дрессировка, поездки/течка/уход, экстренный, ветсводка, ситтер, подписка, настройки, шторки (вердикт, инцидент, «Вырвал», «Как сходил?», реакция), история (день, неделя, календарь, пусто), запас и препарат, правка и удаление, а также все доработки v2 (запуск, разрешения, MergeCard, след удаления, препарат, приглашение, вторая собака, матрица, эпизод, покупка, удаление аккаунта, офлайн). Каждый экран — auto layout из компонентов и переменных, тема задаётся режимом Theme на кадре; подпись над кадром, пояснение — под ним.
- **Togo · экраны-компоненты** — ChoiceChip, FormField, PlanRow, GroupRow (Trailing × Subtitle × Tone, 48 вариантов), NoteRow, ActionCard (MergeCard / PermissionCard / EpisodeCard), HeroMetric, WeekChart, SkillMatrix, CalendarMonth, DogTagCard (жетон), Marker «Да!».
- **TabBar** — вкладки как в чистовике: Сегодня · История · Здоровье · Собака, активная — стекло с акцентом.
- **Переменные** — добавлены `color/system/*` (Live Activity, Dynamic Island), `color/accent/ring`, `type/weight/time`. Все CSS-переменные цвета, отступов, размеров и шрифта из `tokens/` теперь есть в Figma (кроме теней — это стили Elevation, и градиентов).
- **Стили** — Body Emphasized, Title 3 Emphasized, Togo/Screen Title (Rounded 40 — заголовок шапки-плаката).
- Экраны AX1 в Figma не строятся: Dynamic Type там не масштабируется (см. «Ограничения»).

## Запуск (Figma Desktop)

1. Скачайте папку `figma-plugin`.
2. Откройте файл в **приложении Figma** (в браузере плагины из папки не запускаются).
3. **Plugins → Development → Import plugin from manifest…** → `manifest.json`.
4. **Plugins → Development → Graphite → Figma**. 20–60 секунд, итог внизу.

Шрифты до запуска: **SF Pro** и **SF Pro Rounded** (developer.apple.com/fonts), **Material Symbols Rounded** (fonts.google.com/icons). Без них — Inter и кружки вместо иконок, плагин об этом скажет.

## Что изменилось в v3 — новая система Graphite

- Цвета взяты из CSS новой системы Graphite (`tokens/colors.css`, `accents.css`): тёмная — графит #121211 → #262625 → #353534 → #474746; светлая v5 — белый с лёгким холодом (#ECEDF0, белые карточки, fill-2 #D7DBE0), новые error и warning со своими подложками.
- Акценты: **Indigo** (по умолчанию, светлая #0E14A1 с белым текстом), **Orange** (коралл), **Pink** (роза). Lime и Sky убраны. Добавлен `color/accent/muted`. Грань `accent/*/edge` и `glass-tint` посчитаны для каждого акцента — грань кнопки меняется вместе с акцентом.
- Тени Elevation/1 и /2 теперь переключаются темой: в тёмной — волосяная грань (белый 7 и 9 %), в светлой — графитовые тени, в HC — обводка. Цвета теней лежат в `color/effect/*`.
- Слой Togo сохранён: запас `color/stock/*`, статусы `color/togo/*`, все компоненты и экраны «Сегодня».
- `tokens/figma-variables.json` пересобран тем же набором (177 переменных).

## Что было в v2

- Переменные сверены с `tokens/colors.css`: светлая тема v3 (тёплый нейтральный, лайм #C6EF4E), грань `color/fill/edge`, `color/accent/edge`, `color/status/error-edge`, запас `color/stock/low · low-subtle · out · out-subtle`, `type/size/number-hero`, `effect/edge-height-s`. Caption — 13.
- Новые стили: Callout / Subheadline Emphasized, Numbers/Reading 72 и Reading compact 34, Numbers/Unit, Footnote Rounded, Togo/Wordmark, Number Hero 96. Тени без синевы, стекло — блюр 24.
- **Button · грань** — Primary, Secondary, Destructive filled × M / L / XL; грань снизу — тень 3–4 px цвета `*/edge`.
- Страница **Togo · компоненты** и страница **Templates** с экранами по размерам (ниже).

## Togo · смелее (новая страница)

| Компонент | Варианты |
|---|---|
| WalkRing · HeroRing | кольцо прогулки 96 (Walk · Fasting · Overdue) и кольцо-показание 320 для варианта 1a; доля — угол дуги слоя «Progress» |
| PosterCard | **утверждённый** верх «Сегодня» (1b): цветной блок состояния с крупной косточкой — Normal · Fasting · Dose · Alarm |
| VerdictCard | вердикт крупно, «Вывожу» первой |
| LiveActivity | экран блокировки: Walk · Fasting |
| Widget | Small · Medium (акцентная заливка целиком) |
| EmptyState | иллюстрация + текст + кнопка: Feed · Treatment · Family |
| OnboardingStep | иллюстрация «жетон», один вопрос, прогресс |
| Paywall | Togo Pro: иллюстрация, три пункта, два тарифа |
| Illustration | линейные иллюстрации «собака и один предмет», 240 × 160, Scene: feed · treat · family · offline · history · stock · onboarding · paywall; контур привязан к `text/secondary`, акцентная деталь — к `accent/fill` (перекрашиваются с темой) |

Экраны-источники — `Togo Смелее.dc.html`. На странице Templates экраны «Сегодня» собраны в стиле 1b (PosterCard), «Лента прокручена» и «Записать…» — в стиле T5+.

## Togo · компоненты

| Компонент | Варианты |
|---|---|
| StatusBar | Island (54) · Classic (20) |
| TodayHeader | кличка Wordmark · дата · колокольчик и настройки без подложек |
| HomeIndicator | 34 |
| StatusLine | Tone: Success · Warning (только натощак) · Error · Info · Neutral × Action |
| ReadingCard | State: Expanded · Collapsed × Tone: Default · Fasting · Alarm. Косточка: длина заливки — ширина слоя «Fill» (растягивается пропорционально) |
| FeedRow | Kind: Default · Walk · Incident · Fasting × Last. Нет количества — скрыть «Value» |
| SwipeRow | строка, открытая свайпом: Изменить · Удалить |
| ActionBar | Normal · Dose · Alarm × Stacked (AX3) |
| RecordSheet | шторка «Записать…», инцидент первым |
| StockCard | Level: OK · Low · Out; «Купил» только у Low и Out |

Иконка — текстовый слой «Icon · …»: впишите имя глифа Material Symbols (`pets`, `restaurant`…), он сменится.

## Templates · экраны по размерам

Ряд 1 — «Обычный день», тёмная, все размеры: 320 × 568 (проверка 320), SE 375 × 667, 390 × 844, 393 × 852, 402 × 874, 430 × 932, 440 × 956.
Ряды 2–3 — 402 × 874, тёмная и светлая: обычный день, натощак, доза, тревога, лента прокручена (карточка свёрнута), «Записать…» открыта.

Каждый экран — вертикальный auto layout: StatusBar → Body (шапка, строка состояния, карточка, лента, кнопки) → таб-бар → HomeIndicator. Лента растягивается (Fill), поэтому:

- **Нужный размер** — дублируйте ближайший экран (⌘D) и задайте W и H. Поля сами станут 16 (< 375) или 20: у Body привязаны `layout/margin-*` — для узкого экрана переключите переменную на `margin-compact`.
- Лента обрезается снизу с затуханием (слой «Fade mask»). Высота экрана меньше — видно меньше записей, кнопки и таб-бар на месте.
- Сетка 4 колонки с полями экрана — Shift + G.

## Тема и акцент

Выделите экран → правая панель → **Layer → Mode**: Theme (Dark / Light / Dark HC / Light HC), Accent (Indigo / Orange / Pink).

## Ограничения

- Dynamic Type в Figma не масштабируется: для AX-размеров используйте ActionBar Stacked и ReadingCard Collapsed.
- На тарифе Starter у коллекции один режим — Light и HC не создадутся, плагин скажет.
- Медицинский слой (анализы, назначения, визиты) ещё не нарисован — появится в плагине вместе с экранами.
- Иллюстрации на экранах — экземпляры набора Illustration; если SVG не импортировался, плагин напишет об этом в итоге.
