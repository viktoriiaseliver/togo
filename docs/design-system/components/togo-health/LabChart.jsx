import React from "react";
import { Icon } from "../atoms/Icon.jsx";
import { Button } from "../atoms/Button.jsx";
import { Card } from "../molecules/Card.jsx";
import { CardHeader } from "../molecules/CardHeader.jsx";
import { ActionRow } from "../molecules/ActionRow.jsx";
function useWidth() { const ref = React.useRef(null); const [w, setW] = React.useState(300);
  React.useLayoutEffect(() => { const el = ref.current; if (!el) return; const ro = new ResizeObserver(() => setW(el.clientWidth)); ro.observe(el); setW(el.clientWidth); return () => ro.disconnect(); }, []); return [ref, w]; }
export function LabChart({ title = "Т4 общий", unit = "нмоль/л", points = [], range, doses = [], style }) {
  const [ref, W] = useWidth();
  const H = 180, padL = 36, padR = 12, padT = 12, padB = 28;
  const vals = points.map((p) => p.value).concat(range ? [range.low, range.high] : []);
  const lo = Math.min(...vals) * 0.85, hi = Math.max(...vals) * 1.1;
  const x = (i) => padL + (points.length < 2 ? 0 : (i / (points.length - 1)) * (W - padL - padR));
  const y = (v) => padT + (1 - (v - lo) / (hi - lo)) * (H - padT - padB);
  const last = points[points.length - 1];
  const out = (v) => range && (v < range.low || v > range.high);
  return (
    <Card style={style}>
      <CardHeader icon="labs" tone={last && out(last.value) ? "warning" : "accent"} kicker={title + (range ? " · норма " + range.low + "–" + range.high : "")} title={last ? last.value + " " + unit : "—"} subtitle={last ? last.date + (out(last.value) ? " · вне нормы" : " · в норме") : "Анализов пока нет"} />
      <div ref={ref} style={{ width: "100%" }}>
        {points.length > 0 && <svg width={W} height={H} role="img" aria-label={points.map((p) => p.date + " " + p.value).join(", ")} style={{ display: "block", overflow: "visible" }}>
          {range && <rect x={padL} y={y(range.high)} width={W - padL - padR} height={y(range.low) - y(range.high)} rx={8} fill="var(--accent-subtle)" />}
          {range && [range.low, range.high].map((v) => <text key={v} x={padL - 6} y={y(v) + 4} textAnchor="end" fontSize="11" fill="var(--text-secondary)">{v}</text>)}
          {doses.map((d, k) => { const xi = x(d.at); return <g key={k}><line x1={xi} x2={xi} y1={padT} y2={H - padB} stroke="var(--text-disabled)" strokeDasharray="3 4" /><text x={xi + 4} y={padT + 10} fontSize="11" fill="var(--text-secondary)">{d.label}</text></g>; })}
          <polyline points={points.map((p, i) => x(i) + "," + y(p.value)).join(" ")} fill="none" stroke="var(--accent-text)" strokeWidth="2" strokeLinejoin="round" />
          {points.map((p, i) => <g key={i}>
            <circle cx={x(i)} cy={y(p.value)} r={out(p.value) ? 6 : 5} fill={out(p.value) ? "var(--status-error)" : "var(--accent-text)"} stroke="var(--fill-1)" strokeWidth="2" />
            {(i === 0 || i === points.length - 1 || W > 420) && <text x={x(i)} y={H - 8} textAnchor={i === 0 ? "start" : i === points.length - 1 ? "end" : "middle"} fontSize="11" fill="var(--text-secondary)">{p.date}</text>}
          </g>)}
        </svg>}
      </div>
    </Card>
  );
}