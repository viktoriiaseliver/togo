export interface DogProfileProps {
  name: string;
  breed?: string;
  /** «19 марта 2023» */
  birth?: string;
  /** «3 года» */
  age?: string;
  sex?: string;
  weight?: string;
  /** «+0,2 кг за месяц» */
  weightTrend?: string;
  vet?: { name: string; clinic?: string; phone?: string };
  chip?: string;
  onEdit?: () => void;
  onCallVet?: () => void;
  style?: React.CSSProperties;
}
export declare function DogProfile(props: DogProfileProps): JSX.Element;