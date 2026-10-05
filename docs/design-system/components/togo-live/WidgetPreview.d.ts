export interface WidgetPreviewProps {
  size?: "small" | "medium";
  dog?: string;
  /** «2 ч 10 мин» */
  since: string;
  /** «Доза в 19:00» */
  next?: string;
  verdict?: string;
  style?: React.CSSProperties;
}
export declare function WidgetPreview(props: WidgetPreviewProps): JSX.Element;