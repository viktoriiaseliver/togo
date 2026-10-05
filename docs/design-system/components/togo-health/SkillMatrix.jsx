import React from "react";
import { Icon } from "../atoms/Icon.jsx";
import { Button } from "../atoms/Button.jsx";
import { Card } from "../molecules/Card.jsx";
import { CardHeader } from "../molecules/CardHeader.jsx";
import { ActionRow } from "../molecules/ActionRow.jsx";
const LV = ["Не начато", "Учим", "Держит", "Надёжно"];
function Cell({ level = 0, onClick, label }) {
  return (
    <button type="button" onClick={onClick} aria-label={label + ": " + LV[level]} style={{ border: "none", background: "none", padding: 0, cursor: onClick ? "pointer" : "default", minHeight: "var(--size-hit)", display: "flex", alignItems: "center", justifyContent: "center" }}>
      <span style={{ width: 32, height: 32, borderRadius: "50%", display: "flex", alignItems: "center", justifyContent: "center",
        background: level === 3 ? "var(--accent)" : level === 2 ? "var(--accent-subtle)" : "transparent",
        boxShadow: level === 0 ? "inset 0 0 0 1.5px var(--text-disabled)" : level === 1 ? "inset 0 0 0 2px var(--accent-text)" : "none",
        color: level === 3 ? "var(--on-accent)" : "var(--accent-subtle-text)" }}>
        {level === 3 ? <Icon name="check" size={18} weight={500} /> : level === 2 ? <span style={{ width: 10, height: 10, borderRadius: "50%", background: "currentColor" }} /> : null}
      </span>
    </button>
  );
}
export function SkillMatrix({ skills = [], contexts = [], locked = false, onCell, onUnlock, style }) {
  return (
    <Card style={style}>
      <CardHeader icon="school" tone="accent" title="Перенос навыка" subtitle="Навык считается выученным, когда держится в каждом месте" />
      <div style={{ position: "relative" }}>
        <div role="grid" style={{ display: "grid", gridTemplateColumns: "minmax(calc(var(--fs-body) * 4), auto) repeat(" + contexts.length + ", minmax(0, 1fr))", alignItems: "center", gap: "var(--space-4) var(--space-4)", filter: locked ? "blur(3px)" : "none", opacity: locked ? 0.6 : 1 }}>
          <span />
          {contexts.map((c) => <span key={c} style={{ fontSize: "var(--fs-caption-1)", color: "var(--text-secondary)", textAlign: "center", overflowWrap: "break-word", minWidth: 0 }}>{c}</span>)}
          {skills.map((s, i) => (
            <React.Fragment key={s.name}>
              <span style={{ fontSize: "var(--fs-subheadline)", paddingRight: "var(--space-8)", overflowWrap: "break-word" }}>{s.name}</span>
              {contexts.map((c, j) => <Cell key={c} level={s.levels[j] || 0} label={s.name + ", " + c} onClick={!locked && onCell ? () => onCell(i, j) : undefined} />)}
            </React.Fragment>
          ))}
        </div>
        {locked && <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center" }}><Button icon="lock" onClick={onUnlock}>Открыть в Pro</Button></div>}
      </div>
      <div style={{ display: "flex", flexWrap: "wrap", gap: "var(--space-8) var(--space-16)", fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>
        {LV.map((l, i) => <span key={l} style={{ display: "inline-flex", alignItems: "center", gap: "var(--space-8)" }}><span style={{ transform: "scale(.7)", display: "inline-flex", margin: "-8px" }}><Cell level={i} label={l} /></span>{l}</span>)}
      </div>
    </Card>
  );
}