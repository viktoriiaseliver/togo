export interface TripCheck { label: string; done?: boolean }
export interface TripCardProps {
  place: string;
  /** «12–19 окт» */
  dates: string;
  daysLeft?: number;
  checklist?: TripCheck[];
  onToggle?: (index: number) => void;
  style?: React.CSSProperties;
}
export declare function TripCard(props: TripCardProps): JSX.Element;