Строка ленты «Сегодня» и «Дня по часам»: что, сколько, кто, когда.

```jsx
<FeedRow icon="directions_walk" kind="walk" title="Улица" value="18" detail="мин · пописал" who="ты" time="7:10" last />
```

- `kind`: walk (лайм-подложка) · incident (терракот, заголовок красный) · warning (срыв, янтарь) · default.
- `value` — только число, рендерится Rounded акцентом; единица — в `detail`.
- `last` убирает линию под последней строкой.