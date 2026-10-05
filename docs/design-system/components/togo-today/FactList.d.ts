export interface Fact { time: string; what: string; who?: string; pending?: boolean; }
export interface FactListProps { items: Fact[]; onPress?: (f: Fact, i: number) => void; style?: React.CSSProperties; }
export declare function FactList(p: FactListProps): JSX.Element;