export interface SliderProps {
  value?: number;
  min?: number;
  max?: number;
  step?: number;
  onChange?: (v: number) => void;
  label?: string;
  format?: (v: number) => string;
  /** Подписи под шкалой: ["0","1 ч","2 ч"] */
  marks?: string[];
  disabled?: boolean;
  style?: React.CSSProperties;
}
export declare function Slider(props: SliderProps): JSX.Element;