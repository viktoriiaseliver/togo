export interface AvatarProps {
  name: string;
  /** Иконка вместо инициалов: pets для собаки */
  icon?: string;
  src?: string;
  /** s 32 · m 44 · l 52 · xl 88 */
  size?: "s" | "m" | "l" | "xl";
  /** Акцентное кольцо — дежурный */
  ring?: boolean;
  style?: React.CSSProperties;
}
export declare function Avatar(props: AvatarProps): JSX.Element;
export interface AvatarGroupProps { people: AvatarProps[]; max?: number; size?: "s" | "m" | "l"; style?: React.CSSProperties }
export declare function AvatarGroup(props: AvatarGroupProps): JSX.Element;