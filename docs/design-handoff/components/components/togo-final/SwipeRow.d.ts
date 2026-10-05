/** Обёртка строки ленты со свайпом «Изменить / Удалить». Удаление записи — сразу, с тостом «Отменить» 5 с. */
export interface SwipeRowProps { children: React.ReactNode; offset?: number; onEdit?: () => void; onDelete?: () => void; style?: React.CSSProperties; }
export declare function SwipeRow(p: SwipeRowProps): JSX.Element;