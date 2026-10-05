export interface AlertAction { label: string; style?: "default" | "cancel" | "destructive"; onPress?: () => void }
export interface AlertProps {
  open?: boolean;
  title: string;
  message?: string;
  /** 2 — в ряд, 1 или 3+ — столбиком. Отмена — жирная */
  actions: AlertAction[];
  inline?: boolean;
  children?: React.ReactNode;
  style?: React.CSSProperties;
}
/** @startingPoint section="Обратная связь" subtitle="Системный алерт" viewport="700x360" */
export declare function Alert(props: AlertProps): JSX.Element;