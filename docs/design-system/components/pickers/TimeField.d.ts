export interface TimeQuick { label: string; /** минуты от полуночи */ minutes: number }
export interface TimeFieldProps {
  /** "HH:MM" */
  value?: string;
  onChange?: (v: string) => void;
  /** Шаг кнопок ±, мин */
  step?: number;
  /** «Сейчас», «15 мин назад» */
  quick?: TimeQuick[];
  label?: string;
  style?: React.CSSProperties;
}
export declare function TimeField(props: TimeFieldProps): JSX.Element;