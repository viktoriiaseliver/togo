export interface WeekChartDatum { label: string; value: number | null; active?: boolean }
export interface WeekChartProps {
  data: WeekChartDatum[];
  unit?: string;
  /** Пунктир нормы */
  target?: number;
  style?: React.CSSProperties;
}
export declare function WeekChart(props: WeekChartProps): JSX.Element;