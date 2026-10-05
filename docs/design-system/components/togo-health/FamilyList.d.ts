export interface FamilyMember { name: string; /** «Пишет и видит всё» */ role?: string; duty?: boolean; you?: boolean }
export interface FamilyListProps {
  members: FamilyMember[];
  /** Передать дежурство этому человеку */
  onHandOff?: (index: number) => void;
  onInvite?: () => void;
  /** Больше двух — Pro */
  inviteLocked?: boolean;
  style?: React.CSSProperties;
}
export declare function FamilyList(props: FamilyListProps): JSX.Element;