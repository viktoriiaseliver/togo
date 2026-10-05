export interface PermissionCardProps {
  icon?: string;
  title: string;
  /** Зачем это собаке, одной фразой — до системного запроса */
  reason: string;
  /** ask — ещё не спрашивали; denied — отказано; granted — разрешено */
  state?: "ask" | "denied" | "granted";
  onAllow?: () => void;
  onLater?: () => void;
  onSettings?: () => void;
  style?: React.CSSProperties;
}
export declare function PermissionCard(props: PermissionCardProps): JSX.Element;