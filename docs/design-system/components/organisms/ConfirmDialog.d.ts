export interface ConfirmDialogProps {
  open?: boolean;
  message: string;
  /** С числом: «Удалить 3 комнаты» */
  confirmLabel: string;
  onConfirm?: () => void;
  onCancel?: () => void;
  inline?: boolean;
  style?: React.CSSProperties;
}
export declare function ConfirmDialog(props: ConfirmDialogProps): JSX.Element;