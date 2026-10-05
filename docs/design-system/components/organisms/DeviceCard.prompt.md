Карточка 28 pt радиус, мин. 190 pt высота; сетка 2 колонки с зазором 6.
```jsx
<DeviceCard title="Увлажнитель" subtitle="Dyson TP09">
  <Metric value={54} unit="%" /><Toggle checked />
</DeviceCard>
<DeviceCard variant="add" />
```
- `inverse` — одна «активная» карточка на экран.
- `offline` — прочерк вместо значения и «Повторить».