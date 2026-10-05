import React from "react";
import { Icon } from "../atoms/Icon.jsx";

export function SegmentedControl({ options, value, onChange, disabled = false, style }) {
  return (
    <div role="tablist" style={{ display: "inline-flex", background: disabled ? "var(--fill-sunken)" : "var(--fill-track)", borderRadius: "var(--radius-pill)", padding: "var(--space-4)", gap: "var(--space-4)", opacity: disabled ? 0.5 : 1, ...style }}>
      {options.map((o) => {
        const on = o.value === value;
        return (
          <button key={o.value} type="button" role="tab" aria-selected={on} aria-label={o.label} disabled={disabled} onClick={() => onChange && onChange(o.value)}
            style={{ border: "none", cursor: "pointer", minHeight: "var(--size-hit)", minWidth: 44, padding: o.icon ? 0 : "0 20px", borderRadius: "var(--radius-pill)",
              display: "flex", alignItems: "center", justifyContent: "center", fontSize: "var(--fs-subheadline)",
              background: on ? "var(--fill-selected)" : "transparent", color: disabled ? "var(--text-disabled)" : on ? "var(--text-primary)" : "var(--text-secondary)",
              boxShadow: on ? "var(--elev-1)" : "none" }}>
            {o.icon ? <Icon name={o.icon} size={22} fill={on} color={on ? "var(--accent-text)" : undefined} /> : o.label}
          </button>
        );
      })}
    </div>
  );
}