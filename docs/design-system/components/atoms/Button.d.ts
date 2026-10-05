export interface ButtonProps {
  /** primary — одно главное действие на экране; secondary; tinted — пастель акцента; destructive / destructive-filled; surface — на фоне экрана, с тенью; plain — текстовая */
  variant?: "primary" | "secondary" | "tinted" | "destructive" | "destructive-filled" | "surface" | "plain";
  /** s, m — 44; l — 52; xl — 64 */
  size?: "s" | "m" | "l" | "xl";
  /** Имя символа. Без children → круглая кнопка-иконка (нужен label) */
  icon?: string;
  iconPosition?: "leading" | "trailing";
  /** accessibilityLabel для кнопки-иконки */
  label?: string;
  /** Выбранное состояние (тулбар, фильтр) */
  selected?: boolean;
  loading?: boolean;
  disabled?: boolean;
  fullWidth?: boolean;
  /** Цвет иконки/текста поверх варианта */
  color?: string;
  onClick?: () => void;
  children?: React.ReactNode;
  style?: React.CSSProperties;
}
/** @startingPoint section="Атомы" subtitle="Кнопка: текст, текст+иконка, только иконка" viewport="700x520" */
export declare function Button(props: ButtonProps): JSX.Element;