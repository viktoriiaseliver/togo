import React from "react";
import { Icon } from "../atoms/Icon.jsx";
// Строка со свайпом влево: «Изменить» и «Удалить» по 88 pt. offset — текущий сдвиг (0…-176).
export function SwipeRow({ children, offset = 0, onEdit, onDelete, style }) {
  const open = offset < 0;
  const act = (bg, fg, icon, t, fn) => <button onClick={fn} style={{ width: 88, border: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 2, background: bg, color: fg, fontSize: "var(--fs-footnote)", fontFamily: "inherit", cursor: "pointer" }}><Icon name={icon} size={20} />{t}</button>;
  return (
    <div style={{ position: "relative", borderRadius: "var(--radius-row)", overflow: "hidden", ...style }}>
      <div style={{ position: "absolute", right: 0, top: 0, bottom: 0, display: "flex", opacity: open ? 1 : 0 }}>{act("var(--fill-3)", "var(--text-primary)", "edit", "Изменить", onEdit)}{act("var(--status-error)", "var(--on-error)", "delete", "Удалить", onDelete)}</div>
      <div style={{ position: "relative", background: "var(--bg-primary)", transform: "translateX(" + offset + "px)", transition: "transform var(--dur-move) var(--ease-out)", padding: "var(--space-12) var(--space-12) 0" }}>{children}</div>
    </div>
  );
}