export interface SectionHeaderProps {
  title: string;
  action?: string;
  onAction?: () => void;
  style?: React.CSSProperties;
}
export declare function SectionHeader(props: SectionHeaderProps): JSX.Element;