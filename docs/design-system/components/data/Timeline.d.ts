export interface TimelineItem {
  type?: "entry" | "gap" | "now";
  time?: string;
  icon?: string;
  title?: string;
  detail?: string;
  who?: string;
  tone?: "done" | "overdue" | "waiting";
  deleted?: boolean;
  /** Для gap: «4 ч 20 мин без выхода» */
  label?: string;
  warn?: boolean;
  onClick?: () => void;
}
export interface TimelineProps {
  /** Сверху вниз — от новых к старым */
  items: TimelineItem[];
  style?: React.CSSProperties;
}
/** @startingPoint section="Данные" subtitle="Таймлайн дня с промежутками и «сейчас»" viewport="700x560" */
export declare function Timeline(props: TimelineProps): JSX.Element;