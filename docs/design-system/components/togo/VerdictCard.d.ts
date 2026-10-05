export interface VerdictCardProps {
  /** Пять исходов VerdictEngine. Меньше 4 дней данных — всегда unclear */
  outcome?: "urgent" | "likely" | "unclear" | "attention" | "episode";
  /** Почему так: «Последний выход 4 ч 20 мин назад, обычно 3 ч» */
  reason?: string;
  onWalkOut?: () => void;
  onLater?: () => void;
  style?: React.CSSProperties;
}
/** @startingPoint section="Togo" subtitle="Вердикт «просится» — пять исходов" viewport="700x560" */
export declare function VerdictCard(props: VerdictCardProps): JSX.Element;