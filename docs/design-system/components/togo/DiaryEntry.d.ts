export interface DiaryEntryProps {
  time: string;
  icon: string;
  /** Выход, Корм, Стул, Доза, Занятие, Эпизод */
  title: string;
  /** «Как попросил: у двери», «Нормальный» */
  detail?: string;
  /** Кто записал — в общем дневнике */
  who?: string;
  tone?: "done" | "overdue";
  /** След удалённой записи */
  deleted?: boolean;
  onClick?: () => void;
  style?: React.CSSProperties;
}
export declare function DiaryEntry(props: DiaryEntryProps): JSX.Element;