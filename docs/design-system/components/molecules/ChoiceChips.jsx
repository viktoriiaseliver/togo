import React from "react";
export function ChoiceChips({ options, value, onChange, multi = false, style }) {
  const on = (o) => (multi ? (value || []).includes(o) : value === o);
  const tap = (o) => { if (!onChange) return; if (!multi) return onChange(o); const v = value || []; onChange(v.includes(o) ? v.filter((x) => x !== o) : [...v, o]); };
  return (
    <div role={multi ? "group" : "radiogroup"} style={{ display: "flex", flexWrap: "wrap", gap: "var(--gap-cards)", ...style }}>
      {options.map((o) => (
        <button key={o} type="button" role={multi ? "checkbox" : "radio"} aria-checked={on(o)} onClick={() => tap(o)}
          style={{ border: "none", cursor: "pointer", minHeight: "var(--size-hit)", padding: "var(--space-8) var(--space-16)", borderRadius: "var(--radius-pill)", maxWidth: "100%", fontSize: "var(--fs-subheadline)", textAlign: "center",
            background: on(o) ? "var(--accent)" : "var(--fill-2)", color: on(o) ? "var(--on-accent)" : "var(--text-primary)" }}>{o}</button>
      ))}
    </div>
  );
}