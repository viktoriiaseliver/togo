export interface ToastProps {
  /** undo — тёмный с «Отменить»; info — стекло с галочкой; error — с «Повторить» */
  tone?: "undo" | "info" | "error";
  text: string;
  actionLabel?: string;
  onAction?: () => void;
  style?: React.CSSProperties;
}
export declare function Toast(props: ToastProps): JSX.Element;