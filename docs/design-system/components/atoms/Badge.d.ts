export interface BadgeProps {
  tone?: "accent" | "neutral" | "warning" | "error";
  children: React.ReactNode;
  style?: React.CSSProperties;
}
export declare function Badge(props: BadgeProps): JSX.Element;