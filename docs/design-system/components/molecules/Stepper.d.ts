export interface StepperProps {
  value: number;
  onChange?: (v: number) => void;
  min?: number;
  max?: number;
  step?: number;
  unit?: string;
  label?: string;
  style?: React.CSSProperties;
}
export declare function Stepper(props: StepperProps): JSX.Element;