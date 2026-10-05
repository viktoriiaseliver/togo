Поле-пилюля 52 pt; фокус — акцентное кольцо, ошибка — текст и иконка под полем.
```jsx
<TextField value={name} onChange={setName} placeholder="Название" error={!name ? "Название не может быть пустым" : undefined} />
```