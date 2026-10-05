export interface OnboardingStepProps {
  step?: number;
  total?: number;
  icon?: string;
  title: string;
  body?: string;
  /** Глагол: «Дальше», «Начать» */
  primary: string;
  onPrimary?: () => void;
  /** «Пропустить», «Позже» */
  secondary?: string;
  onSecondary?: () => void;
  /** Поле или выбор этого шага */
  children?: React.ReactNode;
  style?: React.CSSProperties;
}
/** @startingPoint section="Сценарии" subtitle="Шаг онбординга" viewport="700x620" */
export declare function OnboardingStep(props: OnboardingStepProps): JSX.Element;