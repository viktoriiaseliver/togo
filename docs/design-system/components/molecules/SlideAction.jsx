import React from "react";
import { Icon } from "../atoms/Icon.jsx";

export function SlideAction({ label, onComplete, disabled = false, style }) {
  const ref = React.useRef(null);
  const [x, setX] = React.useState(0);
  const [done, setDone] = React.useState(false);
  const drag = React.useRef(null);
  const max = () => (ref.current ? ref.current.offsetWidth - 56 : 200);
  const down = (e) => { if (disabled || done) return; drag.current = { x0: e.clientX }; e.currentTarget.setPointerCapture(e.pointerId); };
  const move = (e) => { if (!drag.current) return; setX(Math.max(0, Math.min(max(), e.clientX - drag.current.x0))); };
  const up = () => { if (!drag.current) return; drag.current = null; if (x > max() * 0.8) { setDone(true); setX(max()); onComplete && onComplete(); } else setX(0); };
  if (done) return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", background: "var(--accent)", borderRadius: "var(--radius-pill)", minHeight: 56, paddingLeft: "var(--space-24)", color: "var(--on-accent)", ...style }}>
      <span style={{ fontSize: "var(--fs-body)" }}>{label}</span>
      <div style={{ width: 56, height: 56, borderRadius: "50%", background: "var(--accent-knob)", display: "flex", alignItems: "center", justifyContent: "center" }}><Icon name="check" color="var(--accent)" /></div>
    </div>
  );
  return (
    <div ref={ref} style={{ position: "relative", display: "flex", alignItems: "center", background: disabled ? "var(--fill-sunken)" : "var(--fill-1)", borderRadius: "var(--radius-pill)", minHeight: 56, overflow: "hidden", touchAction: "none", ...style }}>
      {x > 0 && <div style={{ position: "absolute", left: 0, top: 0, bottom: 0, width: x + 56, background: "var(--accent-subtle)", borderRadius: "var(--radius-pill)" }} />}
      <button type="button" aria-label={label} disabled={disabled} onClick={() => { if (!drag.current && x === 0) { /* VoiceOver: обычная кнопка */ } }}
        onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={up}
        style={{ position: "relative", border: "none", padding: 0, width: 56, height: 56, borderRadius: "50%", flexShrink: 0, cursor: disabled ? "default" : "grab",
          transform: `translateX(${x}px)`, transition: drag.current ? "none" : "transform var(--dur-move) var(--ease-out)",
          background: disabled ? "var(--fill-1)" : x > 0 ? "var(--accent)" : "var(--fill-selected)", display: "flex", alignItems: "center", justifyContent: "center" }}>
        {!disabled && <Icon name="chevron_right" color={x > 0 ? "var(--on-accent)" : undefined} />}
      </button>
      <span style={{ position: "relative", marginLeft: "var(--space-16)", fontSize: "var(--fs-body)", color: disabled ? "var(--text-disabled)" : "var(--text-primary)", opacity: x > 0 ? 0 : 1 }}>{label}</span>
    </div>
  );
}