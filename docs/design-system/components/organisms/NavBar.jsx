import React from "react";
import { FitHeader } from "./FitHeader.jsx";
import { IconButton } from "../atoms/IconButton.jsx";
export function NavBar({ title, onBack, leading, trailing, editTitle, style }) {
  if (editTitle !== undefined) return (
    <FitHeader leading={leading} title={editTitle} trailing={trailing} style={style} />
  );
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-12)", ...style }}>
      {(onBack || leading || trailing) && (
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", minHeight: "var(--size-hit)", gap: "var(--space-8)" }}>
          {onBack ? <IconButton icon="chevron_left" label="Назад" size="m" onClick={onBack} /> : leading || <span />}
          <div style={{ display: "flex", gap: "var(--gap-cards)", alignItems: "center", flexWrap: "wrap", justifyContent: "flex-end" }}>{trailing}</div>
        </div>
      )}
      <span style={{ fontSize: "var(--fs-large-title)", lineHeight: 1.1, overflowWrap: "break-word" }}>{title}</span>
    </div>
  );
}