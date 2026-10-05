import React from "react";
import { Card } from "../molecules/Card.jsx";
import { Icon } from "../atoms/Icon.jsx";
import { Button } from "../atoms/Button.jsx";
import { ActionRow } from "../molecules/ActionRow.jsx";
const PRO = ["Матрица переноса навыка", "Вторая собака", "Семья больше двух человек"];
const FREE = ["Окно натощак", "Защита от двойной дозы", "«Как попросил»", "«Не брал еду»", "Отчёты врачу и CSV"];
export function ProCard({ price, trial, onBuy, onRestore, style }) {
  return (
    <Card gap={16} style={style}>
      <span style={{ fontSize: "var(--fs-title-2)", lineHeight: 1.2 }}>Togo Pro</span>
      <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-8)" }}>
        {PRO.map((t) => <span key={t} style={{ display: "grid", gridTemplateColumns: "auto minmax(0,1fr)", gap: "var(--space-12)", alignItems: "center", fontSize: "var(--fs-body)" }}><Icon name="check" size={20} color="var(--accent-text)" />{t}</span>)}
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: "var(--gap-cards)", background: "var(--fill-2)", borderRadius: "var(--radius-inner)", padding: "var(--space-12) var(--space-16)" }}>
        <span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>Бесплатно навсегда</span>
        <span style={{ fontSize: "var(--fs-subheadline)", lineHeight: 1.4 }}>{FREE.join(" · ")}</span>
      </div>
      <ActionRow><Button onClick={onBuy}>{trial ? trial : "Подключить" + (price ? " · " + price : "")}</Button></ActionRow>
      {onRestore && <Button variant="plain" size="m" onClick={onRestore}>Восстановить покупки</Button>}
    </Card>
  );
}