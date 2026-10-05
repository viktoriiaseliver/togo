Меню по долгому нажатию. Дублирует свайп-действия, потому что свайп сам по себе не находится.
```jsx
<ContextMenu items={[{label:"Изменить время",icon:"schedule"},{label:"Удалить",icon:"delete",destructive:true,group:true}]} />
```