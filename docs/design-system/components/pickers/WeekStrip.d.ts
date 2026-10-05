export interface WeekStripProps {
  value?: Date;
  onChange?: (d: Date) => void;
  today?: Date;
  marks?: Record<string, "done" | "overdue">;
  style?: React.CSSProperties;
}
export declare function WeekStrip(props: WeekStripProps): JSX.Element;