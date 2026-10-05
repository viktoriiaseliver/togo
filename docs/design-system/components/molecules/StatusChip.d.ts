export interface StatusChipProps {
  icon?: string;
  title?: string;
  /** Статус словом — не только цветом */
  status?: string;
  tone?: "ok" | "warning" | "error" | "off" | "empty";
  loading?: boolean;
  onClick?: () => void;
  style?: React.CSSProperties;
}
export declare function StatusChip(props: StatusChipProps): JSX.Element;