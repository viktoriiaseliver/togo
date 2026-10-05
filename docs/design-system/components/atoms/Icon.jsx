import React from "react";
export function Icon({ name, size = "var(--icon-size)", fill = false, weight = 300, color, label, style }) {
  return (
    <span aria-label={label} aria-hidden={label ? undefined : true} role={label ? "img" : undefined}
      style={{ fontFamily: "var(--font-icon)", fontSize: size, lineHeight: 1, display: "inline-block",
        fontVariationSettings: `'FILL' ${fill ? 1 : 0}, 'wght' ${weight}`, color, userSelect: "none", ...style }}>{name}</span>
  );
}