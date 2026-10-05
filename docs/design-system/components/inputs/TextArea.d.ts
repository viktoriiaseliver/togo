export interface TextAreaProps {
  value?: string;
  onChange?: (v: string) => void;
  placeholder?: string;
  label?: string;
  /** Лимит символов — показывает счётчик */
  max?: number;
  error?: string;
  disabled?: boolean;
  /** Минимальная высота в строках; растёт с Dynamic Type */
  rows?: number;
  style?: React.CSSProperties;
}
/** @startingPoint section="Ввод" subtitle="Многострочное поле" viewport="700x260" */
export declare function TextArea(props: TextAreaProps): JSX.Element;