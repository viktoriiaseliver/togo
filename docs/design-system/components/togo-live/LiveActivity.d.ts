export interface LiveActivityProps {
  /** walk — прогулка, fast — окно натощак, train — занятие */
  kind?: "walk" | "fast" | "train";
  title?: string;
  elapsed: string;
  detail?: string;
  /** Компактный вид Dynamic Island */
  island?: boolean;
  style?: React.CSSProperties;
}
export declare function LiveActivity(props: LiveActivityProps): JSX.Element;