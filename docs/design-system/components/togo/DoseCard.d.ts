export interface DoseCardProps {
  /** due — по часам; taken — мятная плашка «сделано»; overdue — терракот; waiting — янтарь, окно натощак */
  state?: "due" | "taken" | "overdue" | "waiting";
  name: string;
  /** «200 мкг · 1 таблетка» */
  dose?: string;
  time?: string;
  /** «Уже дал в 07:10 — вторую не записываю», «Кормить через 25 мин» */
  note?: string;
  onGive?: () => void;
  onUndo?: () => void;
  style?: React.CSSProperties;
}
/** @startingPoint section="Togo" subtitle="Доза: пора / дано / пропущена / натощак" viewport="700x520" */
export declare function DoseCard(props: DoseCardProps): JSX.Element;