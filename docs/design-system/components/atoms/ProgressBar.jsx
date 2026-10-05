import React from "react";
export function ProgressBar({ value = 0, style }) {
  const v = Math.max(0, Math.min(100, value));
  return (
    <div role="progressbar" aria-valuenow={v} aria-valuemin={0} aria-valuemax={100} style={{ height: 8, borderRadius: "var(--radius-pill)", background: "var(--fill-1)", overflow: "hidden", ...style }}>
      <div style={{ width: v + "%", height: "100%", background: "var(--accent)", borderRadius: "var(--radius-pill)", transition: "width var(--dur-move) var(--ease-out)" }} />
    </div>
  );
}