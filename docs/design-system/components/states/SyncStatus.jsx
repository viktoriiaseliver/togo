import React from "react";
import { Icon } from "../atoms/Icon.jsx";
const S = {
  synced: ["cloud_done", "var(--text-secondary)", "Всё у всех"],
  pending: ["cloud_upload", "var(--text-secondary)", "Отправляется"],
  offline: ["cloud_off", "var(--status-warning)", "Нет сети · сохранено на телефоне"],
  error: ["sync_problem", "var(--status-error)", "Не отправилось"],
};
export function SyncStatus({ state = "synced", detail, onRetry, style }) {
  const [ic, col, text] = S[state];
  return (
    <div role="status" style={{ display: "inline-flex", flexWrap: "wrap", alignItems: "center", gap: "var(--space-4) var(--space-8)", minHeight: 32, padding: "var(--space-4) var(--space-12)", borderRadius: "var(--radius-pill)", background: "var(--fill-2)", fontSize: "var(--fs-footnote)", color: col, maxWidth: "100%", ...style }}>
      <span className="material-symbols-rounded" aria-hidden="true" style={{ fontSize: "var(--icon-size-s)" }}>{ic}</span>
      <span>{text}{detail ? " · " + detail : ""}</span>
      {state === "error" && onRetry && <button type="button" onClick={onRetry} style={{ border: "none", background: "none", padding: 0, minHeight: "var(--size-hit)", cursor: "pointer", color: "var(--accent-text)", fontSize: "var(--fs-footnote)" }}>Повторить</button>}
    </div>
  );
}