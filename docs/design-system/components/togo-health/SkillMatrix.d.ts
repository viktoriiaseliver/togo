export interface Skill { name: string; /** 0–3 на каждое место */ levels: number[] }
export interface SkillMatrixProps {
  skills: Skill[];
  /** «Дом», «Двор», «Парк», «Город» */
  contexts: string[];
  /** Pro: без подписки — размыто с кнопкой */
  locked?: boolean;
  onCell?: (skill: number, context: number) => void;
  onUnlock?: () => void;
  style?: React.CSSProperties;
}
/** @startingPoint section="Togo · здоровье и семья" subtitle="Матрица переноса навыка (Pro)" viewport="700x420" */
export declare function SkillMatrix(props: SkillMatrixProps): JSX.Element;