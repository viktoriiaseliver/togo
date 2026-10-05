export interface EmptyStateProps {
  icon?: string;
  /** Что здесь будет */
  title: string;
  /** Почему пусто */
  message?: string;
  actionLabel?: string;
  actionIcon?: string;
  /** Акцентная кнопка — только для первого запуска */
  primary?: boolean;
  onAction?: () => void;
  tone?: "neutral" | "error" | "warning";
  /** В карточке fill-1 */
  card?: boolean;
  style?: React.CSSProperties;
}
export declare function EmptyState(props: EmptyStateProps): JSX.Element;