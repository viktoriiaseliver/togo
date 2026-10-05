import React from "react";
import { Icon } from "../atoms/Icon.jsx";
const SZ = { s: 32, m: 44, l: 52, xl: 88 };
const initials = (n = "") => n.trim().split(/\s+/).slice(0, 2).map((w) => w[0]).join("").toUpperCase();
export function Avatar({ name, icon, src, size = "m", ring = false, style }) {
  const d = SZ[size] || SZ.m;
  return (
    <span role="img" aria-label={name} style={{ width: d, height: d, flexShrink: 0, borderRadius: "50%", background: "var(--fill-2)", color: "var(--text-primary)", display: "inline-flex", alignItems: "center", justifyContent: "center",
      fontSize: d * 0.38, fontWeight: 500, overflow: "hidden", boxShadow: ring ? "0 0 0 2px var(--bg-primary), 0 0 0 4px var(--accent)" : "none", ...style }}>
      {src ? <img src={src} alt="" style={{ width: "100%", height: "100%", objectFit: "cover" }} /> : icon ? <Icon name={icon} size={Math.round(d * 0.5)} /> : initials(name)}
    </span>
  );
}
export function AvatarGroup({ people = [], max = 3, size = "s", style }) {
  const shown = people.slice(0, max), rest = people.length - shown.length;
  const d = SZ[size] || SZ.s;
  return (
    <span aria-label={people.map((p) => p.name).join(", ")} style={{ display: "inline-flex", alignItems: "center", ...style }}>
      {shown.map((p, i) => <Avatar key={i} {...p} size={size} style={{ marginLeft: i ? -d * 0.3 : 0, boxShadow: "0 0 0 2px var(--bg-primary)" }} />)}
      {rest > 0 && <span style={{ marginLeft: -d * 0.3, width: d, height: d, borderRadius: "50%", background: "var(--fill-3)", boxShadow: "0 0 0 2px var(--bg-primary)", display: "inline-flex", alignItems: "center", justifyContent: "center", fontSize: "var(--fs-caption-1)" }}>+{rest}</span>}
    </span>
  );
}