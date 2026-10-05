export interface SegmentOption { value: string; label: string; icon?: string }
export interface SegmentedControlProps {
  /** До 4 пунктов */
  options: SegmentOption[];
  value: string;
  onChange?: (v: string) => void;
  disabled?: boolean;
  style?: React.CSSProperties;
}
export declare function SegmentedControl(props: SegmentedControlProps): JSX.Element;