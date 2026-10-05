Шапка «Отмена · Заголовок · Готово», которая сама адаптируется: если заголовок не помещается, он встаёт отдельной строкой над кнопками (как в iOS при AX-размерах). Используется в Sheet и NavBar.
```jsx
<FitHeader leading={<Button variant="plain">Отмена</Button>} title="Новая комната" trailing={<Button variant="plain">Готово</Button>} />
```