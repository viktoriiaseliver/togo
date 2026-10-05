export interface MediaItem { src?: string; kind?: "image" | "file"; caption?: string; uploading?: boolean }
export interface MediaGridProps {
  items: MediaItem[];
  onAdd?: () => void;
  onOpen?: (index: number) => void;
  max?: number;
  style?: React.CSSProperties;
}
export declare function MediaGrid(props: MediaGridProps): JSX.Element;