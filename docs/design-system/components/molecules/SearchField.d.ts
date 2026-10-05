export interface SearchFieldProps {
  value: string;
  onChange?: (v: string) => void;
  onCancel?: () => void;
  placeholder?: string;
  style?: React.CSSProperties;
}
export declare function SearchField(props: SearchFieldProps): JSX.Element;