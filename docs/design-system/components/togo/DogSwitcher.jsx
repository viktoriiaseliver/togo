import React from "react";
import { Icon } from "../atoms/Icon.jsx";
export function DogSwitcher({ dogs, value, onChange, onAdd, style }) {
  return (
    <div role="tablist" style={{ display: "flex", flexWrap: "wrap", gap: "var(--gap-cards)", ...style }}>
      {dogs.map((d) => { const on = d.id === value; return (
        <button key={d.id} type="button" role="tab" aria-selected={on} onClick={() => onChange && onChange(d.id)}
          style={{ border: "none", cursor: "pointer", minHeight: "var(--size-hit)", padding: "var(--space-8) var(--space-16) var(--space-8) var(--space-8)", borderRadius: "var(--radius-pill)", display: "flex", alignItems: "center", gap: "var(--space-8)", fontSize: "var(--fs-subheadline)",
            background: on ? "var(--fill-selected)" : "var(--fill-1)", color: "var(--text-primary)", boxShadow: on ? "inset 0 0 0 2px var(--accent)" : "var(--elev-1)" }}>
          <span style={{ width: 32, height: 32, borderRadius: "50%", background: "var(--fill-2)", display: "flex", alignItems: "center", justifyContent: "center" }}><Icon name="pets" size={18} /></span>{d.name}
        </button>); })}
      {onAdd && <button type="button" onClick={onAdd} aria-label="Добавить собаку" style={{ border: "none", cursor: "pointer", minHeight: "var(--size-hit)", minWidth: 44, borderRadius: "var(--radius-pill)", background: "var(--fill-1)", boxShadow: "var(--elev-1)", display: "flex", alignItems: "center", justifyContent: "center", color: "var(--accent-text)" }}><Icon name="add" size={22} /></button>}
    </div>
  );
}