export interface ProCardProps {
  price?: string;
  /** Показывать только если StoreKit подтвердил оффер и право (isEligibleForIntroOffer) */
  trial?: string;
  onBuy?: () => void;
  onRestore?: () => void;
  style?: React.CSSProperties;
}
export declare function ProCard(props: ProCardProps): JSX.Element;