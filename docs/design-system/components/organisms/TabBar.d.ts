export interface TabItem { value: string; label: string; icon: string }
export interface TabBarProps {
  items: TabItem[];
  value: string;
  onChange?: (v: string) => void;
  /** Ширина < 375 или AX-размер: подпись активного таба скрыта */
  compact?: boolean;
  style?: React.CSSProperties;
}
export declare function TabBar(props: TabBarProps): JSX.Element;