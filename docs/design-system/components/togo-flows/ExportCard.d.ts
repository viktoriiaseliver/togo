export interface ExportInclude { label: string; on: boolean }
export interface ExportCardProps {
  /** «23 сен – 2 окт» — открывает Calendar */
  range: string;
  onRange?: () => void;
  formats?: string[];
  format?: string;
  onFormat?: (f: string) => void;
  /** Выходы, стул, дозы, анализы, эпизоды */
  includes?: ExportInclude[];
  onToggleInclude?: (index: number) => void;
  state?: "idle" | "loading" | "done";
  onExport?: () => void;
  style?: React.CSSProperties;
}
export declare function ExportCard(props: ExportCardProps): JSX.Element;