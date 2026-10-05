export interface QuickLogItem { value: string; label: string; icon: string; /** «2 ч назад» */ since?: string; active?: boolean }
export interface QuickLogProps {
  /** 3–4 действия: выход, корм, стул, вода */
  items: QuickLogItem[];
  onLog?: (value: string) => void;
  style?: React.CSSProperties;
}
/** @startingPoint section="Togo" subtitle="Быстрая запись в два тапа" viewport="700x200" */
export declare function QuickLog(props: QuickLogProps): JSX.Element;