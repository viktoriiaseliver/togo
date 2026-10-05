export interface ReadingPart { v: string; u?: string; }
/**
 * Карточка показания «Сегодня» (T5+). collapse — прогресс прокрутки ленты 0…1 (scrollTop / 150).
 * @startingPoint section="Togo · Финал" subtitle="Показание, полоса до следующего, «дальше»" viewport="420x320"
 */
export interface ReadingCardProps {
  icon?: string; label: string; parts: ReadingPart[];
  tone?: "default" | "timer" | "muted" | "alarm";
  bar?: { pct: number; from: string; to: string; tone?: "accent" | "warning" | "muted" };
  next?: { icon: string; title: string; short: string; when: string; tone?: "default" | "error" };
  collapse?: number; style?: React.CSSProperties;
}
export declare function ReadingCard(p: ReadingCardProps): JSX.Element;