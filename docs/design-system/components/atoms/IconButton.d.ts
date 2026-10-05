export interface IconButtonProps {
  icon: string;
  /** Обязателен: accessibilityLabel */
  label: string;
  size?: "s" | "m" | "l" | "xl";
  selected?: boolean;
  disabled?: boolean;
  /** По умолчанию surface */
  variant?: "primary" | "secondary" | "tinted" | "destructive" | "surface" | "plain";
  color?: string;
  onClick?: () => void;
  style?: React.CSSProperties;
}
/** Сокращение для <Button icon label /> без текста. */
export declare function IconButton(props: IconButtonProps): JSX.Element;