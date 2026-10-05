/**
 * Запас лекарства или корма по уровням: ok > 7 дней, low ≤ 7 (--stock-low), out ≤ 3 (--stock-out).
 * @startingPoint section="Togo · Финал" subtitle="Запас с уровнями и «Купил»" viewport="420x260"
 */
export interface StockCardProps { icon?: string; name: string; perDay?: string; left: string; unit: string; until: string; daysLeft: number; total?: number; status?: string; onBought?: () => void; style?: React.CSSProperties; }
export declare function StockCard(p: StockCardProps): JSX.Element;
export declare function stockLevel(daysLeft: number): "ok" | "low" | "out";