export interface SyncStatusProps {
  /** synced — у всех; pending — отправляется; offline — только на телефоне; error — не дошло */
  state?: "synced" | "pending" | "offline" | "error";
  /** «у мамы ещё нет», «3 записи» */
  detail?: string;
  onRetry?: () => void;
  style?: React.CSSProperties;
}
export declare function SyncStatus(props: SyncStatusProps): JSX.Element;