Строка списка 64 pt, радиус 24, каждая строка — отдельная плашка с зазором 6.
```jsx
<ListRow icon="kitchen" title="Кухня" subtitle="3 устройства" chevron onClick={open} />
<ListRow title="Уведомления" trailing={<Toggle checked />} />
<ListRow title="Удалить комнату" destructive />
```
- Свайп-действия — оберните в `SwipeRow`-логику экрана (см. ui_kits).