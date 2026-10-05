export interface SkeletonProps {
  width?: string | number;
  height?: string | number;
  /** Круг вместо пилюли */
  round?: boolean;
  style?: React.CSSProperties;
}
export declare function Skeleton(props: SkeletonProps): JSX.Element;