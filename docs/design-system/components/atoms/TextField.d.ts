export interface TextFieldProps {
  value: string;
  onChange?: (v: string) => void;
  placeholder?: string;
  /** Текст ошибки под полем; включает красное кольцо */
  error?: string;
  disabled?: boolean;
  clearable?: boolean;
  autoFocus?: boolean;
  style?: React.CSSProperties;
}
export declare function TextField(props: TextFieldProps): JSX.Element;