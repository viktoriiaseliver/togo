export interface ChoiceChipsProps {
  options: string[];
  /** string для одиночного выбора, string[] для multi */
  value?: string | string[] | null;
  onChange?: (v: any) => void;
  multi?: boolean;
  style?: React.CSSProperties;
}
export declare function ChoiceChips(props: ChoiceChipsProps): JSX.Element;