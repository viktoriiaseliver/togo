export interface DateRowProps {
  icon?: string;
  label: string;
  /** «Сегодня, 08:10», «12–19 окт» */
  value: string;
  onClick?: () => void;
  style?: React.CSSProperties;
}
export declare function DateRow(props: DateRowProps): JSX.Element;