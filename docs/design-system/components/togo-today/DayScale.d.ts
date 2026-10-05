export interface DayEvent { start: number; end?: number; kind: "outside" | "dose" | "fasting" | "incident" | "plan"; }
export interface DayScaleProps { events: DayEvent[]; now?: number; from?: number; to?: number; style?: React.CSSProperties; }
export declare function DayScale(p: DayScaleProps): JSX.Element;