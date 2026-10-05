Выбор времени записи: ±5 минут и быстрые варианты. В SwiftUI — DatePicker(.hourAndMinute) в стиле .compact; здесь — крупные цели для пальца.
```jsx
<TimeField value={t} onChange={setT} quick={[{label:"Сейчас",minutes:now},{label:"15 мин назад",minutes:now-15}]} />
```