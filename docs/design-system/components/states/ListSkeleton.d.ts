export interface ListSkeletonProps { rows?: number; icon?: boolean; style?: React.CSSProperties }
/** Каркас списка при первой загрузке — повторяет форму ListRow. */
export declare function ListSkeleton(props: ListSkeletonProps): JSX.Element;
export interface RefreshIndicatorProps {
  state?: "idle" | "pulling" | "loading" | "error";
  /** «2 мин назад» */
  updated?: string;
  style?: React.CSSProperties;
}
/** Строка над списком при обновлении свайпом вниз (.refreshable). */
export declare function RefreshIndicator(props: RefreshIndicatorProps): JSX.Element;