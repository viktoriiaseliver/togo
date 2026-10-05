export interface ToggleProps {
  checked: boolean;
  onChange?: (next: boolean) => void;
  disabled?: boolean;
  label?: string;
  style?: React.CSSProperties;
}
export declare function Toggle(props: ToggleProps): JSX.Element;