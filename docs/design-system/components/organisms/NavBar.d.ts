export interface NavBarProps {
  /** Large Title */
  title?: string;
  onBack?: () => void;
  leading?: React.ReactNode;
  trailing?: React.ReactNode;
  /** Режим правки: строка «leading · заголовок · trailing» */
  editTitle?: string;
  style?: React.CSSProperties;
}
export declare function NavBar(props: NavBarProps): JSX.Element;