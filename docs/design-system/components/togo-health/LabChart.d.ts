export interface LabPoint { date: string; value: number }
export interface LabChartProps {
  title?: string;
  unit?: string;
  points: LabPoint[];
  /** Коридор нормы лаборатории */
  range?: { low: number; high: number };
  /** Смены дозы: индекс точки, после которой сменили, и подпись */
  doses?: { at: number; label: string }[];
  style?: React.CSSProperties;
}
export declare function LabChart(props: LabChartProps): JSX.Element;