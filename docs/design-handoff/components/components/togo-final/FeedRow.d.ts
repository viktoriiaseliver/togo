/** Строка ленты: новое сверху, линия между кружками, время нейтральное. */
export interface FeedRowProps { icon: string; kind?: "walk" | "incident" | "warning" | "default"; title: string; value?: string; detail?: string; who?: string; time: string; last?: boolean; onClick?: () => void; style?: React.CSSProperties; }
export declare function FeedRow(p: FeedRowProps): JSX.Element;