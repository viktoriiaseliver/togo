export interface WalkMark { value: string; label: string; count?: number }
export interface WalkBarProps {
  /** От старта, «12:40» */
  elapsed?: string;
  /** Отметки на ходу: пописал, покакал, занятие */
  marks?: WalkMark[];
  onMark?: (value: string) => void;
  onFinish?: () => void;
  style?: React.CSSProperties;
}
export declare function WalkBar(props: WalkBarProps): JSX.Element;