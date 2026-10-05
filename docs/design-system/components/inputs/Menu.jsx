import React from "react";
import { Icon } from "../atoms/Icon.jsx";
export function Menu({ label, value, options = [], onChange, placeholder = "Выбрать", disabled = false, style }) {
  const [open, setOpen] = React.useState(false);
  const cur = options.find((o) => (o.value ?? o) === value);
  const text = cur ? (cur.label ?? cur) : placeholder;
  return (
    <div style={{ position: "relative", display: "flex", flexDirection: "column", gap: "var(--space-4)", ...style }}>
      <button type="button" disabled={disabled} aria-haspopup="listbox" aria-expanded={open} onClick={() => setOpen(!open)}
        style={{ border: "none", cursor: disabled ? "default" : "pointer", minHeight: "var(--size-row)", padding: "var(--pad-row-y) var(--pad-row)", borderRadius: "var(--radius-row)",
          background: disabled ? "var(--fill-sunken)" : "var(--fill-1)", boxShadow: disabled ? "none" : "var(--elev-1)", display: "flex", flexWrap: "wrap", alignItems: "center", gap: "var(--space-4) var(--space-12)", textAlign: "left", color: "var(--text-primary)" }}>
        {label && <span style={{ flex: "1 1 0", minWidth: "min(100%, calc(var(--fs-body) * 6))", fontSize: "var(--fs-body)" }}>{label}</span>}
        <span style={{ marginLeft: "auto", display: "flex", alignItems: "center", gap: "var(--space-4)", fontSize: "var(--fs-body)", color: disabled ? "var(--text-disabled)" : cur ? "var(--accent-text)" : "var(--text-secondary)" }}>{text}<Icon name="unfold_more" size={18} /></span>
      </button>
      {open && <>
        <div onClick={() => setOpen(false)} style={{ position: "fixed", inset: 0, zIndex: 9 }} />
        <div role="listbox" style={{ position: "absolute", top: "100%", right: 0, marginTop: "var(--space-4)", zIndex: 10, minWidth: "min(260px, 100%)", maxWidth: "100%", background: "var(--glass)", backdropFilter: "blur(var(--blur-glass))", WebkitBackdropFilter: "blur(var(--blur-glass))", borderRadius: "var(--radius-row)", boxShadow: "var(--elev-2)", overflow: "hidden" }}>
          {options.map((o, i) => { const v = o.value ?? o, on = v === value; return (
            <button key={String(v)} type="button" role="option" aria-selected={on} onClick={() => { onChange && onChange(v); setOpen(false); }}
              style={{ width: "100%", border: "none", background: "none", cursor: "pointer", minHeight: "var(--size-button)", padding: "var(--pad-row-y) var(--pad-row)", display: "grid", gridTemplateColumns: "20px minmax(0,1fr)", gap: "var(--space-12)", alignItems: "center", textAlign: "left", fontSize: "var(--fs-body)", color: "var(--text-primary)", borderTop: i ? "1px solid var(--separator)" : "none" }}>
              <span>{on && <Icon name="check" size={20} color="var(--accent-text)" />}</span><span>{o.label ?? o}</span>
            </button>); })}
        </div>
      </>}
    </div>
  );
}