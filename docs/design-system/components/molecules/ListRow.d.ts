export interface ListRowProps {
  icon?: string;
  title: string;
  subtitle?: string;
  value?: string;
  /** Тумблер, статус, ручка перетаскивания */
  trailing?: React.ReactNode;
  /** Кружок выбора в режиме правки */
  leading?: React.ReactNode;
  chevron?: boolean;
  /** Центрированная красная строка «Удалить …» */
  /** Подложка иконки: accent / warning / error */
  iconTone?: "accent" | "warning" | "error";
  subtitleTone?: "accent";
  destructive?: boolean;
  onClick?: () => void;
  style?: React.CSSProperties;
}
/** @startingPoint section="Молекулы" subtitle="Строка списка 64 pt" viewport="700x620" */
export declare function ListRow(props: ListRowProps): JSX.Element;