export interface Reminder { icon?: string; title: string; /** «07:00», «каждые 4 ч» */ time: string; repeat?: string; on: boolean }
export interface ReminderScheduleProps {
  items: Reminder[];
  onToggle?: (index: number, on: boolean) => void;
  onEdit?: (index: number) => void;
  quiet?: { on: boolean; from: string; to: string };
  onQuiet?: (on: boolean) => void;
  /** Time Sensitive / Critical для дозы */
  critical?: boolean;
  onCritical?: (on: boolean) => void;
  style?: React.CSSProperties;
}
export declare function ReminderSchedule(props: ReminderScheduleProps): JSX.Element;