export interface MetricProps {
  /** null/undefined → прочерк и «Нет данных», никогда не 0 */
  value?: string | number | null;
  unit?: string;
  caption?: string;
  size?: "xl" | "l" | "m";
  color?: string;
  style?: React.CSSProperties;
}
export declare function Metric(props: MetricProps): JSX.Element;