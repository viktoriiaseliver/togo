import React from "react";
import { Card } from "../molecules/Card.jsx";
import { Icon } from "../atoms/Icon.jsx";
import { CardHeader } from "../molecules/CardHeader.jsx";
import { Button } from "../atoms/Button.jsx";
import { ActionRow } from "../molecules/ActionRow.jsx";
export function InviteCard({ from, dog, role = "Пишет и видит всё", state = "pending", onAccept, onDecline, style }) {
  return (
    <Card gap={14} style={style}>
      <CardHeader avatar={<Icon name="pets" size={28} />} kicker={from + " зовёт в дневник"} title={dog} />
      <span style={{ fontSize: "var(--fs-subheadline)", lineHeight: 1.4, color: "var(--text-secondary)" }}>{role}. Записи общие, дежурство можно передать.</span>
      {state === "pending" && <ActionRow><Button onClick={onAccept}>Присоединиться</Button><Button variant="secondary" onClick={onDecline}>Не сейчас</Button></ActionRow>}
      {state === "joining" && <ActionRow><Button loading>Присоединиться</Button></ActionRow>}
      {state === "expired" && <span style={{ fontSize: "var(--fs-subheadline)", color: "var(--status-warning)" }}>Ссылка устарела. Попроси {from} прислать новую.</span>}
      {state === "joined" && <span style={{ fontSize: "var(--fs-subheadline)", color: "var(--accent-text)", display: "flex", alignItems: "center", gap: "var(--gap-cards)" }}><Icon name="check_circle" size={18} fill />Ты в дневнике</span>}
    </Card>
  );
}