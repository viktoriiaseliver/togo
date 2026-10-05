import React from "react";
import { Icon } from "../atoms/Icon.jsx";
import { Button } from "../atoms/Button.jsx";
import { Card } from "../molecules/Card.jsx";
import { CardHeader } from "../molecules/CardHeader.jsx";
import { ActionRow } from "../molecules/ActionRow.jsx";
import { Avatar } from "../media/Avatar.jsx";
import { ListRow } from "../molecules/ListRow.jsx";
export function DogProfile({ name, breed, birth, age, sex, weight, weightTrend, vet, chip, onEdit, onCallVet, style }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--gap-cards)", ...style }}>
      <Card style={{ alignItems: "center", textAlign: "center", gap: "var(--space-12)" }}>
        <Avatar name={name} icon="pets" size="xl" />
        <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-4)" }}>
          <span style={{ fontSize: "var(--fs-title-1)", lineHeight: 1.15 }}>{name}</span>
          <span style={{ fontSize: "var(--fs-subheadline)", color: "var(--text-secondary)" }}>{[breed, sex, age].filter(Boolean).join(" · ")}</span>
        </div>
        {onEdit && <Button variant="secondary" size="m" icon="edit" onClick={onEdit}>Изменить</Button>}
      </Card>
      {weight && <ListRow icon="monitor_weight" title="Вес" subtitle={weightTrend} value={weight} />}
      {birth && <ListRow icon="cake" title="День рождения" value={birth} />}
      {chip && <ListRow icon="memory" title="Чип" value={chip} />}
      {vet && <ListRow icon="stethoscope" title={vet.name} subtitle={vet.clinic} trailing={<Button icon="call" label={"Позвонить " + vet.name} variant="tinted" size="m" onClick={onCallVet} />} />}
    </div>
  );
}