import React from "react";
import { Icon } from "../atoms/Icon.jsx";
// Вместо кнопок, когда записывает другой (ситтер) или доступ только на просмотр (врач).
export function ReadOnlyBar({ icon = "visibility", text, style }) {
  return (
    <div role="note" style={{ minHeight: "var(--size-button-xl)", borderRadius: "var(--radius-pill)", boxShadow: "inset 0 0 0 1.5px var(--separator)", color: "var(--text-secondary)", display: "flex", alignItems: "center", gap: "var(--space-12)", padding: "0 var(--space-20)", fontSize: "var(--fs-subheadline)", ...style }}>
      <Icon name={icon} size={22} />{text}
    </div>
  );
}