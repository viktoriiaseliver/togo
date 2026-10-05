Ответ на «просится?». Кнопка «Вывожу» — первая и акцентная во всех пяти исходах: приложение не знает лучше хозяина.
```jsx
<VerdictCard outcome="likely" reason="Последний выход 3 ч 40 мин назад, обычно 3 ч" onWalkOut={start} onLater={close} />
<VerdictCard outcome="unclear" reason="Мало данных: нужно хотя бы 4 дня записей" onWalkOut={start} />
```