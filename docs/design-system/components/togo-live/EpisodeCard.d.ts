export interface EpisodeCardProps {
  /** «Жидкий стул», «Рвота» */
  title?: string;
  started: string;
  /** Сколько раз за эпизод */
  count?: number;
  signs?: string[];
  onAdd?: () => void;
  onEnd?: () => void;
  onCall?: () => void;
  style?: React.CSSProperties;
}
export declare function EpisodeCard(props: EpisodeCardProps): JSX.Element;