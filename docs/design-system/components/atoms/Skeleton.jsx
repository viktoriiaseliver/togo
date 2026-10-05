import React from "react";
export function Skeleton({ width = "100%", height = 12, round = false, style }) {
  return <div aria-hidden="true" style={{ width, height, borderRadius: round ? "50%" : "var(--radius-pill)", background: "var(--fill-1)", flexShrink: 0, ...style }} />;
}