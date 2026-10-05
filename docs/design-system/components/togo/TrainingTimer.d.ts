export interface TrainingTimerProps {
  /** Навык: «Место», «Ко мне» */
  skill: string;
  elapsed?: string;
  /** MarkerEngine: задержка между «он сделал» и маркером */
  lastDelayMs?: number;
  /** После 3 минут прогресс не пишется */
  overLimit?: boolean;
  reps?: number;
  onMarker?: () => void;
  onFinish?: () => void;
  style?: React.CSSProperties;
}
export declare function TrainingTimer(props: TrainingTimerProps): JSX.Element;