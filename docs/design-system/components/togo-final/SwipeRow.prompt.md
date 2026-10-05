Свайп по записи: «Изменить» и «Удалить». Полный свайп удаляет сразу.

```jsx
<SwipeRow offset={-176} onEdit={openEdit} onDelete={remove}><FeedRow … /></SwipeRow>
```

- Запись удаляется без подтверждения, затем `Toast tone="undo"` с «Отменить» 5 с.
- Препарат, участник семьи, собака — только через `ConfirmDialog`.