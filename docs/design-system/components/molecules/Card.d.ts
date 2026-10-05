export interface CardProps {
  /** default — fill-1 + elev-1; subtle/warning/error — пастель без тени; inverse — одна на экран */
  tone?: "default" | "subtle" | "warning" | "error" | "inverse";
  /** По умолчанию var(--pad-card) = 18 */
  pad?: number | string;
  gap?: number;
  as?: string;
  children?: React.ReactNode;
  style?: React.CSSProperties;
}
/** Единая поверхность карточки. Все карточки системы строятся на ней. */
export declare function Card(props: CardProps): JSX.Element;