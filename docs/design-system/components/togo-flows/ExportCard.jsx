import React from "react";
import { Card } from "../molecules/Card.jsx";
import { Icon } from "../atoms/Icon.jsx";
import { ChoiceChips } from "../molecules/ChoiceChips.jsx";
import { SelectCircle } from "../atoms/SelectCircle.jsx";
import { Button } from "../atoms/Button.jsx";
import { ActionRow } from "../molecules/ActionRow.jsx";
export function ExportCard({ range, onRange, formats = ["PDF врачу", "CSV"], format, onFormat, includes = [], onToggleInclude, state = "idle", onExport, style }) {
  return (
    <Card gap={14} style={style}>
      <span style={{ fontSize: "var(--fs-title-3)", lineHeight: 1.2 }}>Отчёт</span>
      <button type="button" onClick={onRange} style={{ border: "none", cursor: "pointer", minHeight: "var(--size-button)", padding: "var(--space-8) var(--space-16)", borderRadius: "var(--radius-pill)", background: "var(--fill-2)", display: "flex", flexWrap: "wrap", justifyContent: "space-between", alignItems: "center", gap: "var(--space-4) var(--space-12)", color: "var(--text-primary)", fontSize: "var(--fs-body)" }}>
        <span>Период</span><span style={{ color: "var(--accent-text)" }}>{range}</span>
      </button>
      <ChoiceChips options={formats} value={format} onChange={onFormat} />
      {includes.length > 0 && <div style={{ display: "flex", flexDirection: "column" }}>
        {includes.map((c, i) => (
          <button key={c.label} type="button" role="checkbox" aria-checked={c.on} onClick={() => onToggleInclude && onToggleInclude(i)} style={{ border: "none", background: "none", cursor: "pointer", minHeight: "var(--size-hit)", padding: 0, display: "grid", gridTemplateColumns: "26px minmax(0,1fr)", gap: "var(--space-12)", alignItems: "center", textAlign: "left", color: "var(--text-primary)", fontSize: "var(--fs-body)" }}>
            <SelectCircle checked={c.on} style={{ pointerEvents: "none" }} />{c.label}
          </button>))}
      </div>}
      <ActionRow><Button icon={state === "done" ? "check" : "ios_share"} loading={state === "loading"} onClick={onExport}>{state === "done" ? "Готово · отправить" : "Собрать отчёт"}</Button></ActionRow>
    </Card>
  );
}