export interface DoseChange { date: string; dose: string; reason?: string }
export interface TreatmentPlanProps {
  drug: string;
  /** «200 мкг» */
  dose: string;
  times?: string[];
  since: string;
  /** «40 мин без еды» */
  fasting?: string;
  /** От новой к старой */
  history?: DoseChange[];
  onChangeDose?: () => void;
  onPause?: () => void;
  style?: React.CSSProperties;
}
export declare function TreatmentPlan(props: TreatmentPlanProps): JSX.Element;