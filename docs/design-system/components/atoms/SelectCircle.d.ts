export interface SelectCircleProps {
  checked: boolean;
  disabled?: boolean;
  onChange?: (next: boolean) => void;
  style?: React.CSSProperties;
}
export declare function SelectCircle(props: SelectCircleProps): JSX.Element;