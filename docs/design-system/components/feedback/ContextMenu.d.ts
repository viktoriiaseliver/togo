export interface MenuItem { label: string; icon?: string; destructive?: boolean; /** Отделить группу */ group?: boolean; onPress?: () => void }
export interface ContextMenuProps {
  items: MenuItem[];
  /** Поднятый элемент над меню */
  preview?: React.ReactNode;
  style?: React.CSSProperties;
}
export declare function ContextMenu(props: ContextMenuProps): JSX.Element;