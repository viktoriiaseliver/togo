import React from "react";
export function TextArea({ value = "", onChange, placeholder, label, max, error, disabled = false, rows = 3, style }) {
  const [focus, setFocus] = React.useState(false);
  const ring = error ? "var(--status-error)" : focus ? "var(--accent)" : "transparent";
  return (
    <label style={{ display: "flex", flexDirection: "column", gap: "var(--space-4)", ...style }}>
      {label && <span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)", padding: "0 var(--space-4)" }}>{label}</span>}
      <textarea value={value} disabled={disabled} rows={rows} placeholder={placeholder} maxLength={max}
        onChange={(e) => onChange && onChange(e.target.value)} onFocus={() => setFocus(true)} onBlur={() => setFocus(false)}
        style={{ resize: "none", border: "none", outline: "none", font: "inherit", fontSize: "var(--fs-body)", lineHeight: 1.4, color: disabled ? "var(--text-disabled)" : "var(--text-primary)",
          background: disabled ? "var(--fill-sunken)" : "var(--fill-1)", borderRadius: "var(--radius-row)", padding: "var(--pad-inner) var(--pad-row)", minHeight: "calc(var(--fs-body) * 1.4 * " + rows + " + 28px)",
          boxShadow: "inset 0 0 0 2px " + ring + (disabled ? "" : ", var(--elev-1)"), boxSizing: "border-box", width: "100%" }} />
      <span style={{ display: "flex", justifyContent: "space-between", flexWrap: "wrap", gap: "var(--space-8)", padding: "0 var(--space-4)", fontSize: "var(--fs-footnote)" }}>
        <span style={{ color: "var(--status-error)" }}>{error}</span>
        {max && <span style={{ color: value.length >= max ? "var(--status-warning)" : "var(--text-secondary)", fontVariantNumeric: "tabular-nums" }}>{value.length} / {max}</span>}
      </span>
    </label>
  );
}