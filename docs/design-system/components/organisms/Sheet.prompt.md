Шит редактирования: ручка, «Отмена · Заголовок · Готово», форма. Позиционируется absolute внутри экрана.
```jsx
<Sheet title="Комната" onCancel={close} onDone={save} doneDisabled={!name}>
  <TextField value={name} onChange={setName} />
</Sheet>
```