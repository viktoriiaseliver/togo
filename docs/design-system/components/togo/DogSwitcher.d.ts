export interface Dog { id: string; name: string }
export interface DogSwitcherProps {
  dogs: Dog[];
  value: string;
  onChange?: (id: string) => void;
  /** Вторая собака — Pro */
  onAdd?: () => void;
  style?: React.CSSProperties;
}
export declare function DogSwitcher(props: DogSwitcherProps): JSX.Element;