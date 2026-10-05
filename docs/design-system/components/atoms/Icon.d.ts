export interface IconProps {
  /** Material Symbols name (в коде iOS — соответствующий SF Symbol) */
  name: string;
  size?: string | number;
  /** Заливка — только для выбранного состояния */
  fill?: boolean;
  weight?: number;
  color?: string;
  /** accessibilityLabel для иконки без подписи */
  label?: string;
  style?: React.CSSProperties;
}
export declare function Icon(props: IconProps): JSX.Element;