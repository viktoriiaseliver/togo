export interface InlineAlertProps {
  tone?: "info" | "success" | "warning" | "error";
  title: string;
  message?: string;
  actionLabel?: string;
  onAction?: () => void;
  onClose?: () => void;
  style?: React.CSSProperties;
}
export declare function InlineAlert(props: InlineAlertProps): JSX.Element;