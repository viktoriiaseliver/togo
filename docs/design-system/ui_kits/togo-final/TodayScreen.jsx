// «Сегодня» T5+: карточка вне скролла, лента новое сверху, сжатие по прокрутке, свайп/удаление с тостом.
const STATES = {
  normal: { label: "С прогулки", parts: [{ v: "2", u: "ч" }, { v: "10", u: "мин" }], bar: { pct: 62, from: "гулял в 7:28", to: "обычно до 11:00" }, next: { icon: "directions_walk", title: "Выход около 11:00", short: "11:00", when: "через 1 ч 20" }, primary: ["pets", "Просится"], s1: ["directions_walk", "Гулять"], s2: ["add", "Записать…"] },
  fasting: { label: "С прогулки", parts: [{ v: "1", u: "ч" }, { v: "01", u: "мин" }], status: { tone: "warning", icon: "no_meals", text: "Не кормить ещё 19 мин" }, bar: { pct: 37, from: "доза в 8:00", to: "еда в 8:30", tone: "warning" }, next: { icon: "restaurant", title: "Завтрак 65 г", short: "8:30", when: "в 8:30" }, primary: ["pets", "Просится"], s1: ["directions_walk", "Гулять"], s2: ["add", "Записать…"] },
  dose: { label: "С прогулки", parts: [{ v: "1", u: "ч" }, { v: "35", u: "мин" }], status: { tone: "success", icon: "medication", text: "Доза 20:00 · 0,1 мг", actionLabel: "Беру на себя", actionIcon: "back_hand" }, next: { icon: "restaurant", title: "Ужин 65 г", short: "20:30", when: "в 20:30" }, primary: ["medication", "Дал дозу"], s1: ["pets", "Просится"], s2: ["add", "Записать…"] },
  alarm: { tone: "alarm", label: "С прогулки", parts: [{ v: "0", u: "ч" }, { v: "24", u: "мин" }], status: { tone: "error", icon: "emergency_home", text: "Кровь в стуле — позвоните врачу" }, next: { icon: "local_hospital", title: "Вет+ · открыт до 20:00", short: "Вет+", when: "+33 4 93…", tone: "error" }, primary: ["call", "Позвонить врачу"], danger: true, s1: ["description", "Что сказать"], s2: ["schedule", "Подожду час"] }
};
const FEED = [
  { id: 1, icon: "school", title: "Занятие", detail: "у двери, 10 мин", who: "ты", time: "18:12" },
  { id: 2, icon: "cookie", title: "Лакомство", value: "1", detail: "шт · сыр", who: "ты", time: "18:05" },
  { id: 3, icon: "directions_walk", kind: "walk", title: "Улица", value: "25", detail: "мин · пописал", who: "Аня", time: "17:40" },
  { id: 4, icon: "grass", title: "Стул", detail: "норма", who: "мама", time: "13:30" },
  { id: 5, icon: "restaurant", title: "Еда", value: "65", detail: "г · съел", who: "мама", time: "13:05" },
  { id: 6, icon: "directions_walk", kind: "walk", title: "Улица", value: "19", detail: "мин · пописал", who: "ты", time: "12:22" },
  { id: 7, icon: "sick", kind: "incident", title: "Вырвал", detail: "травой", who: "ты", time: "11:20" },
  { id: 8, icon: "medication", title: "Доза", value: "0,1", detail: "мг", who: "мама", time: "8:00" },
  { id: 9, icon: "directions_walk", kind: "walk", title: "Улица", value: "18", detail: "мин · пописал", who: "ты", time: "7:10" }
];
const RECORD = [["grass", "Стул"], ["restaurant", "Еда"], ["cookie", "Лакомство"], ["school", "Занятие"], ["edit_note", "Заметка"], ["work", "Весь день"]];

function TodayScreen({ state, onRecord }) {
  const G = window.Graphite;
  const { ReadingCard, FeedRow, SwipeRow, StatusLine, Button, Toast, Icon } = G;
  const S = STATES[state];
  const [p, setP] = React.useState(0);
  const [feed, setFeed] = React.useState(FEED);
  const [swiped, setSwiped] = React.useState(null);
  const [undo, setUndo] = React.useState(null);
  React.useEffect(() => { if (!undo) return; const t = setTimeout(() => setUndo(null), 5000); return () => clearTimeout(t); }, [undo]);
  const remove = (e) => { setFeed((f) => f.filter((x) => x.id !== e.id)); setSwiped(null); setUndo(e); };
  const restore = () => { setFeed((f) => [...f, undo].sort((a, b) => b.id < a.id ? 1 : -1)); setUndo(null); };
  return (
    <div style={{ height: "100%", display: "flex", flexDirection: "column" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", minHeight: 44, padding: "4px 20px 0" }}>
        <span style={{ display: "flex", alignItems: "baseline", gap: 8 }}><span style={{ fontFamily: "var(--font-rounded)", fontWeight: 300, fontSize: 28 }}>Стич</span><span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>чт, 4 окт</span></span>
        <span style={{ display: "flex", color: "var(--text-secondary)" }}>{["notifications", "settings"].map((n) => <span key={n} style={{ width: 44, height: 44, display: "flex", alignItems: "center", justifyContent: "center" }}><Icon name={n} size={24} /></span>)}</span>
      </div>
      {S.status && <div style={{ padding: "0 20px" }}><StatusLine {...S.status} /></div>}
      <div style={{ padding: "12px 20px" }}><ReadingCard {...S} collapse={p} /></div>
      <div onScroll={(e) => setP(Math.min(1, e.currentTarget.scrollTop / 150))} style={{ flex: 1, minHeight: 0, overflowY: "auto", scrollbarWidth: "none", padding: "0 20px", WebkitMaskImage: "linear-gradient(to bottom,transparent 0,#000 12px,#000 calc(100% - 96px),transparent 100%)", maskImage: "linear-gradient(to bottom,transparent 0,#000 12px,#000 calc(100% - 96px),transparent 100%)" }}>
        <div style={{ padding: "8px 0 96px" }}>
          {feed.map((e, i) => <SwipeRow key={e.id} offset={swiped === e.id ? -176 : 0} onEdit={() => setSwiped(null)} onDelete={() => remove(e)}><div onClick={() => setSwiped(swiped === e.id ? null : e.id)} style={{ cursor: "pointer" }}><FeedRow {...e} last={i === feed.length - 1} /></div></SwipeRow>)}
          <span style={{ display: "flex", alignItems: "center", gap: 12, minHeight: 44, paddingLeft: 12, fontSize: "var(--fs-footnote)", color: "var(--accent-text)" }}><Icon name="schedule" size={18} />День по часам</span>
        </div>
      </div>
      <div style={{ position: "relative", display: "flex", flexDirection: "column", gap: 12, padding: "0 20px 4px" }}>
        {undo && <div style={{ position: "absolute", left: 16, right: 16, bottom: "calc(100% + 12px)" }}><Toast tone="undo" text={"Удалено · " + undo.title.toLowerCase() + " " + undo.time} actionLabel="Отменить" onAction={restore} /></div>}
        <Button size="xl" edge fullWidth variant={S.danger ? "destructive-filled" : "primary"} icon={S.primary[0]}>{S.primary[1]}</Button>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}><Button variant="secondary" edge icon={S.s1[0]}>{S.s1[1]}</Button><Button variant="secondary" edge icon={S.s2[0]} onClick={S.s2[1] === "Записать…" ? onRecord : undefined}>{S.s2[1]}</Button></div>
      </div>
    </div>
  );
}

function RecordSheet({ onClose, onPick }) {
  const { Icon } = window.Graphite;
  return (
    <div style={{ position: "absolute", inset: 0, zIndex: 5 }}>
      <div onClick={onClose} style={{ position: "absolute", inset: 0, background: "var(--scrim)" }} />
      <div style={{ position: "absolute", left: 8, right: 8, bottom: 8, borderRadius: "var(--radius-sheet-floating)", background: "var(--glass-regular)", backdropFilter: "blur(var(--blur-glass)) saturate(var(--glass-saturate))", WebkitBackdropFilter: "blur(var(--blur-glass)) saturate(var(--glass-saturate))", boxShadow: "var(--glass-shadow)", padding: "8px 16px 24px", display: "flex", flexDirection: "column", gap: 12 }}>
        <span style={{ alignSelf: "center", width: 36, height: 5, borderRadius: 3, background: "var(--separator)" }} />
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}><button onClick={onClose} aria-label="Закрыть" style={{ width: 44, height: 44, border: 0, borderRadius: "50%", background: "var(--glass-clear)", color: "var(--text-primary)", cursor: "pointer" }}><Icon name="close" size={22} /></button><span style={{ display: "flex", flexDirection: "column", alignItems: "center" }}><span style={{ fontSize: "var(--fs-headline)", fontWeight: 600 }}>Записать</span><span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>сейчас · изменить время</span></span><span style={{ width: 44 }} /></div>
        <button onClick={() => onPick("Инцидент")} style={{ display: "flex", alignItems: "center", gap: 12, minHeight: 64, padding: "0 16px 0 12px", border: 0, borderRadius: "var(--radius-row)", background: "var(--error-subtle)", color: "var(--status-error)", fontFamily: "inherit", textAlign: "left", cursor: "pointer" }}><span style={{ width: 40, height: 40, borderRadius: "50%", background: "var(--fill-1)", display: "flex", alignItems: "center", justifyContent: "center" }}><Icon name="emergency_home" size={22} /></span><span style={{ flex: 1, display: "flex", flexDirection: "column" }}><span style={{ fontSize: "var(--fs-callout)", fontWeight: 600 }}>Инцидент</span><span style={{ fontSize: "var(--fs-footnote)" }}>рвота, лужа, стул дома</span></span><Icon name="chevron_right" size={20} /></button>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8 }}>{RECORD.map(([i, t]) => <button key={t} onClick={() => onPick(t)} style={{ display: "flex", flexDirection: "column", justifyContent: "space-between", gap: 8, minHeight: 104, padding: "12px 16px", border: 0, borderRadius: "var(--radius-row)", background: "var(--fill-1)", color: "var(--text-primary)", fontFamily: "inherit", textAlign: "left", cursor: "pointer" }}><span style={{ width: 40, height: 40, borderRadius: "50%", background: "var(--fill-2)", display: "flex", alignItems: "center", justifyContent: "center" }}><Icon name={i} size={22} /></span><span style={{ fontSize: "var(--fs-callout)" }}>{t}</span></button>)}</div>
      </div>
    </div>
  );
}
Object.assign(window, { TodayScreen, RecordSheet });
