import React from "react";
import { Icon } from "../atoms/Icon.jsx";
import { Button } from "../atoms/Button.jsx";
import { Card } from "../molecules/Card.jsx";
import { CardHeader } from "../molecules/CardHeader.jsx";
import { ActionRow } from "../molecules/ActionRow.jsx";
import { Avatar } from "../media/Avatar.jsx";
import { ListRow } from "../molecules/ListRow.jsx";
import { Badge } from "../atoms/Badge.jsx";
export function FamilyList({ members = [], onHandOff, onInvite, inviteLocked = false, style }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--gap-cards)", ...style }}>
      {members.map((m, i) => (
        <ListRow key={m.name} leading={<Avatar name={m.name} ring={m.duty} />} title={m.name + (m.you ? " (ты)" : "")} subtitle={m.role}
          trailing={m.duty ? <Badge tone="accent">Дежурит</Badge> : onHandOff ? <Button variant="plain" size="m" onClick={() => onHandOff(i)}>Передать</Button> : null} />
      ))}
      {onInvite && <Button variant="secondary" fullWidth icon={inviteLocked ? "lock" : "person_add"} onClick={onInvite}>{inviteLocked ? "Третий человек — в Pro" : "Пригласить"}</Button>}
    </div>
  );
}