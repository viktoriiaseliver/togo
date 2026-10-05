export interface MorningBriefProps {
  greeting?: string;
  /** Всё, что не прерывало ночью и ждало утра */
  items?: string[];
  onOpen?: () => void;
  onDismiss?: () => void;
  style?: React.CSSProperties;
}
export declare function MorningBrief(props: MorningBriefProps): JSX.Element;