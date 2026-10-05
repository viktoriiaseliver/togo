import React from "react";
export function useFitHeader() {
  const ref = React.useRef(null);
  const need = React.useRef(0);
  const [stacked, setStacked] = React.useState(false);
  React.useLayoutEffect(() => {
    const el = ref.current; if (!el || typeof ResizeObserver === "undefined") return;
    const check = () => {
      const w = el.clientWidth;
      if (!stacked) {
        const [a, t, b] = el.children; if (!t) return;
        const ws = t.style.whiteSpace; t.style.whiteSpace = "nowrap";
        const natural = t.scrollWidth, avail = t.clientWidth;
        t.style.whiteSpace = ws;
        if (natural > avail + 0.5) { need.current = a.scrollWidth + natural + b.scrollWidth + 16; setStacked(true); }
      } else if (need.current && w >= need.current) setStacked(false);
    };
    check();
    const ro = new ResizeObserver(check); ro.observe(el);
    return () => ro.disconnect();
  });
  return [ref, stacked];
}
export function FitHeader({ leading, title, trailing, titleStyle, style }) {
  const [ref, stacked] = useFitHeader();
  const t = <span data-one-line={stacked ? undefined : ""} style={{ fontSize: "var(--fs-headline)", fontWeight: 600, textAlign: "center", minWidth: 0, overflowWrap: "break-word", ...titleStyle }}>{title}</span>;
  if (stacked) return (
    <div ref={ref} style={{ display: "flex", flexDirection: "column", gap: "var(--space-4)", ...style }}>
      <span style={{ display: "none" }} />{React.cloneElement(t, { style: { ...t.props.style, textAlign: "left" } })}<span style={{ display: "none" }} />
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: "var(--space-8)" }}>{leading || <span />}{trailing || <span />}</div>
    </div>
  );
  return (
    <div ref={ref} style={{ display: "grid", gridTemplateColumns: "auto minmax(0,1fr) auto", alignItems: "center", gap: "var(--space-8)", minHeight: "var(--size-hit)", ...style }}>
      {leading || <span />}{t}{trailing || <span />}
    </div>
  );
}