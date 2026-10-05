export interface EditBarProps {
  count?: number;
  onDelete?: () => void;
  /** Например «Переместить»; иначе слева счётчик выбранного */
  secondaryLabel?: string;
  onSecondary?: () => void;
  style?: React.CSSProperties;
}
export declare function EditBar(props: EditBarProps): JSX.Element;