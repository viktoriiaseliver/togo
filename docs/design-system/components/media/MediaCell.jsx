import React from "react";
import { Icon } from "../atoms/Icon.jsx";
export function MediaGrid({ items = [], onAdd, onOpen, max = 6, style }) {
  const tile = { aspectRatio: "1", borderRadius: "var(--radius-inner)", overflow: "hidden", position: "relative", border: "none", padding: 0, cursor: "pointer" };
  return (
    <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(max(88px, calc(var(--fs-body) * 5)), 1fr))", gap: "var(--gap-cards)", ...style }}>
      {items.map((m, i) => (
        <button key={i} type="button" onClick={() => onOpen && onOpen(i)} aria-label={m.caption || "Вложение " + (i + 1)} style={{ ...tile, background: "var(--fill-2)" }}>
          {m.src ? <img src={m.src} alt="" style={{ width: "100%", height: "100%", objectFit: "cover", display: "block" }} />
            : <span style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center", color: "var(--text-secondary)" }}><Icon name={m.kind === "file" ? "description" : "image"} size={28} /></span>}
          {m.caption && <span style={{ position: "absolute", left: 6, right: 6, bottom: 6, padding: "var(--space-4) var(--space-8)", borderRadius: "var(--radius-pill)", background: "var(--glass)", backdropFilter: "blur(var(--blur-glass))", WebkitBackdropFilter: "blur(var(--blur-glass))", fontSize: "var(--fs-caption-1)", color: "var(--text-primary)", textAlign: "center", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{m.caption}</span>}
          {m.uploading && <span style={{ position: "absolute", inset: 0, background: "var(--scrim)", display: "flex", alignItems: "center", justifyContent: "center", color: "var(--on-scrim)" }}><Icon name="progress_activity" /></span>}
        </button>
      ))}
      {onAdd && items.length < max && <button type="button" onClick={onAdd} aria-label="Добавить фото" style={{ ...tile, background: "transparent", boxShadow: "inset 0 0 0 1.5px var(--separator)", color: "var(--accent-text)", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: "var(--space-4)", fontSize: "var(--fs-footnote)" }}><Icon name="add_a_photo" />Добавить</button>}
    </div>
  );
}