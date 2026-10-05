export interface MenuOption { value: string; label: string }
export interface MenuProps {
  label?: string;
  value?: string;
  options: (MenuOption | string)[];
  onChange?: (v: string) => void;
  placeholder?: string;
  disabled?: boolean;
  style?: React.CSSProperties;
}
export declare function Menu(props: MenuProps): JSX.Element;