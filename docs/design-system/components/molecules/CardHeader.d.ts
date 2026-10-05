export interface CardHeaderProps {
  icon?: string;
  /** Вместо иконки — аватар 52 */
  avatar?: React.ReactNode;
  tone?: "neutral" | "accent" | "warning" | "error";
  /** Надзаголовок: «Поездка · 12–19 окт» → заголовок title-3 */
  kicker?: string;
  title: React.ReactNode;
  subtitle?: string;
  /** Число, бейдж, время — уходит на свою строку, если тесно */
  trailing?: React.ReactNode;
  style?: React.CSSProperties;
}
/** Шапка любой карточки: иконка · надзаголовок · заголовок · хвост. */
export declare function CardHeader(props: CardHeaderProps): JSX.Element;