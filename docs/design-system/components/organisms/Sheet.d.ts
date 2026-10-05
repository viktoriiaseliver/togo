export interface SheetProps {
  open?: boolean;
  title: string;
  onCancel?: () => void;
  onDone?: () => void;
  /** «Готово» неактивна, пока нет изменений или есть ошибка */
  doneDisabled?: boolean;
  /** Без скрима и позиционирования — для превью */
  inline?: boolean;
  children?: React.ReactNode;
  style?: React.CSSProperties;
}
export declare function Sheet(props: SheetProps): JSX.Element;