export interface ActionRowProps {
  /** Кнопки Button; первая — главная */
  children: React.ReactNode;
  style?: React.CSSProperties;
}
export declare function ActionRow(props: ActionRowProps): JSX.Element;