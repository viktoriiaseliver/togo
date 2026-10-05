export interface DeviceCardProps {
  variant?: "default" | "inverse" | "add" | "loading" | "offline";
  title?: string;
  subtitle?: string;
  subtitleTone?: "accent" | "secondary" | "error";
  /** Тело: Metric, Toggle, ProgressBar, кнопки */
  children?: React.ReactNode;
  onClick?: () => void;
  style?: React.CSSProperties;
}
/** @startingPoint section="Организмы" subtitle="Карточка 28: данные, inverse, пусто, загрузка" viewport="700x460" */
export declare function DeviceCard(props: DeviceCardProps): JSX.Element;