export interface FastingWindowProps {
  /** До дозы или после — FeedingGate знает обе стороны */
  phase?: "before" | "after";
  minutesLeft?: number;
  /** 0–1 */
  progress?: number;
  until?: string;
  style?: React.CSSProperties;
}
export declare function FastingWindow(props: FastingWindowProps): JSX.Element;