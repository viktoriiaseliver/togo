export interface CalendarProps {
  value?: Date;
  onChange?: (d: Date) => void;
  /** "2026-10-01": "done" | "overdue" — точка под днём */
  marks?: Record<string, "done" | "overdue">;
  min?: Date;
  max?: Date;
  today?: Date;
  style?: React.CSSProperties;
}
/** @startingPoint section="Выбор даты" subtitle="Календарь месяца с отметками" viewport="700x480" */
export declare function Calendar(props: CalendarProps): JSX.Element;