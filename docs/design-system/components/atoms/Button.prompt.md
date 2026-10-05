Единая кнопка. Четыре формы — одним компонентом:
- только текст: `<Button>Записать</Button>`
- иконка + текст: `<Button icon="add">Добавить</Button>`, иконка справа — `iconPosition="trailing"`
- только иконка (круг): `<Button icon="settings" label="Настройки" variant="surface" />`
- текстовая: `<Button variant="plain">Изменить</Button>`

Варианты: primary (одна на экран), secondary, tinted, destructive, destructive-filled, surface, plain. Размеры s / m (44), l (52), xl (64). Состояния: selected, loading, disabled.
Ряд из 2–3 кнопок — только в `ActionRow`.