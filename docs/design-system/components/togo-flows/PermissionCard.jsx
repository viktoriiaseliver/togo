import React from "react";
import { Card } from "../molecules/Card.jsx";
import { Icon } from "../atoms/Icon.jsx";
import { CardHeader } from "../molecules/CardHeader.jsx";
import { Button } from "../atoms/Button.jsx";
import { ActionRow } from "../molecules/ActionRow.jsx";
export function PermissionCard({ icon = "notifications", title, reason, state = "ask", onAllow, onLater, onSettings, style }) {
  const denied = state === "denied";
  return (
    <Card gap={14} style={style}>
      <CardHeader icon={icon} tone={denied ? "warning" : "accent"} title={title} subtitle={denied ? "Сейчас выключено. Включить можно только в Настройках iPhone." : reason} />
      {state === "granted"
        ? <span style={{ fontSize: "var(--fs-subheadline)", color: "var(--accent-text)", display: "flex", alignItems: "center", gap: "var(--gap-cards)" }}><Icon name="check_circle" size={18} fill />Разрешено</span>
        : denied
          ? <ActionRow><Button variant="secondary" icon="settings" onClick={onSettings}>Открыть Настройки</Button></ActionRow>
          : <ActionRow><Button onClick={onAllow}>Разрешить</Button>{onLater && <Button variant="secondary" onClick={onLater}>Позже</Button>}</ActionRow>}
    </Card>
  );
}