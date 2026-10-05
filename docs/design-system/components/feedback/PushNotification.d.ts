export interface PushAction { label: string; destructive?: boolean; onPress?: () => void }
export interface PushNotificationProps {
  app?: string;
  /** Иконка приложения (Material Symbols). Радиус = radius-row − pad-inner */
  appIcon?: string;
  time?: string;
  title: string;
  body: string;
  /** Действия из уведомления: «Дал», «Через 10 мин» */
  actions?: PushAction[];
  style?: React.CSSProperties;
}
export declare function PushNotification(props: PushNotificationProps): JSX.Element;