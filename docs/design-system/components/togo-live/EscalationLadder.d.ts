export interface EscalationStep { who: string; /** «Уведомление», «Звонок», «Критическое» */ how: string; time: string }
export interface EscalationLadderProps {
  steps: EscalationStep[];
  /** Индекс текущей ступени */
  current?: number;
  onAck?: () => void;
  style?: React.CSSProperties;
}
export declare function EscalationLadder(props: EscalationLadderProps): JSX.Element;