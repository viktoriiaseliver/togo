import React from "react";
import { Toggle } from "../atoms/Toggle.jsx";
import { ListRow } from "../molecules/ListRow.jsx";
import { SectionHeader } from "../molecules/SectionHeader.jsx";
export function ReminderSchedule({ items = [], onToggle, onEdit, quiet, onQuiet, critical, onCritical, style }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--gap-cards)", ...style }}>
      {items.map((it, i) => (
        <ListRow key={i} icon={it.icon || "schedule"} title={it.title} subtitle={it.time + (it.repeat ? " · " + it.repeat : "")} subtitleTone={it.on ? "accent" : undefined}
          onClick={onEdit ? () => onEdit(i) : undefined} trailing={<Toggle checked={it.on} label={it.title} onChange={(v) => onToggle && onToggle(i, v)} />} />
      ))}
      {(quiet || critical != null) && <SectionHeader title="Тишина" style={{ marginTop: "var(--space-12)" }} />}
      {quiet && <ListRow icon="bedtime" title="Тихие часы" subtitle={quiet.from + "–" + quiet.to + " · ждёт утреннего брифа"} trailing={<Toggle checked={quiet.on} label="Тихие часы" onChange={(v) => onQuiet && onQuiet(v)} />} />}
      {critical != null && <ListRow icon="notification_important" iconTone="error" title="Доза пробивает тишину" subtitle="Только доза и окно натощак" trailing={<Toggle checked={critical} label="Доза пробивает тишину" onChange={(v) => onCritical && onCritical(v)} />} />}
    </div>
  );
}