import React from "react";
export function ActionRow({ children, style }) {
  return (
    <div style={{ display: "flex", flexWrap: "wrap", gap: "var(--gap-cards)", ...style }}>
      {React.Children.toArray(children).filter(Boolean).map((c, i) => (
        <div key={i} style={{ flex: "1 0 auto", maxWidth: "100%", display: "flex" }}>{React.cloneElement(c, { fullWidth: true })}</div>
      ))}
    </div>
  );
}