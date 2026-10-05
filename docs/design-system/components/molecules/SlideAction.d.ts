export interface SlideActionProps {
  label: string;
  /** Срабатывает на 80 % длины */
  onComplete?: () => void;
  disabled?: boolean;
  style?: React.CSSProperties;
}
export declare function SlideAction(props: SlideActionProps): JSX.Element;