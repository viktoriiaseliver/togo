export interface FitHeaderProps {
  leading?: React.ReactNode;
  title: React.ReactNode;
  trailing?: React.ReactNode;
  titleStyle?: React.CSSProperties;
  style?: React.CSSProperties;
}
/** Шапка «действие · заголовок · действие»: если заголовок не помещается (320 pt, AX), уходит отдельной строкой над кнопками. */
export declare function FitHeader(props: FitHeaderProps): JSX.Element;
export declare function useFitHeader(): [React.RefObject<HTMLDivElement>, boolean];