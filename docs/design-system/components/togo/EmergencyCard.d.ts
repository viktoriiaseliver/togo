export interface EmergencyCardProps {
  vetName: string;
  phone?: string;
  /** Признаки «звони сейчас» */
  callNow?: string[];
  /** Признаки «наблюдай» */
  watch?: string[];
  onCall?: () => void;
  /** Карточка с ответами врачу из дневника */
  onReport?: () => void;
  style?: React.CSSProperties;
}
export declare function EmergencyCard(props: EmergencyCardProps): JSX.Element;