Состояния загрузки. ListSkeleton — только при первой загрузке, дольше 300 мс; при обновлении показываем старые данные и RefreshIndicator сверху.
```jsx
<ListSkeleton rows={3} />
<RefreshIndicator state="loading" />
```