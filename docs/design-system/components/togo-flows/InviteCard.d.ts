export interface InviteCardProps {
  /** «Вика» */
  from: string;
  dog: string;
  role?: string;
  state?: "pending" | "joining" | "expired" | "joined";
  onAccept?: () => void;
  onDecline?: () => void;
  style?: React.CSSProperties;
}
export declare function InviteCard(props: InviteCardProps): JSX.Element;