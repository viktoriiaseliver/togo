export interface MergeEntry { what: string; who: string; time: string }
export interface MergeCardProps {
  title?: string;
  first: MergeEntry;
  second: MergeEntry;
  onMerge?: () => void;
  onKeep?: () => void;
  style?: React.CSSProperties;
}
export declare function MergeCard(props: MergeCardProps): JSX.Element;