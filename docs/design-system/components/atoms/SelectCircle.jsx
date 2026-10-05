import React from "react";
import { Icon } from "./Icon.jsx";
export function SelectCircle({ checked, disabled = false, onChange, style }) {
  return (
    <span role="checkbox" aria-checked={checked} onClick={() => !disabled && onChange && onChange(!checked)}
      style={{ width: 26, height: 26, borderRadius: "50%", flexShrink: 0, display: "inline-flex", alignItems: "center", justifyContent: "center",
        background: checked ? "var(--accent)" : "transparent", boxShadow: checked ? "none" : `inset 0 0 0 1.5px var(${disabled ? "--text-disabled" : "--text-secondary"})`,
        opacity: disabled ? 0.5 : 1, cursor: disabled ? "default" : "pointer", ...style }}>
      {checked && <Icon name="check" size={18} weight={500} color="var(--on-accent)" />}
    </span>
  );
}