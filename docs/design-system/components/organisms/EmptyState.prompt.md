Пустое состояние: иконка в круге → что здесь будет → почему пусто → одно действие.
```jsx
<EmptyState title="Пока пусто" message="Добавьте первую комнату" actionLabel="Добавить" primary onAction={add} />
<EmptyState icon="wifi_off" tone="error" title="Нет соединения" actionLabel="Повторить" />
```