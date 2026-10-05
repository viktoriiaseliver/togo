// Запас: уровни ok / low (≤ 7 дн) / out (≤ 3 дн) и шторка «Купил» со сроком годности.
function StockScreen() {
  const { StockCard, Button, Icon, Toast } = window.Graphite;
  const [buy, setBuy] = React.useState(null);
  const [items, setItems] = React.useState([
    { id: "levo", name: "Левотироксин", perDay: "1,5 таб. в день", left: "4", unit: "таб", until: "сб 6 окт", daysLeft: 2, status: "Кончится в субботу" },
    { id: "food", icon: "restaurant", name: "Корм", perDay: "130 г в день", left: "0,8", unit: "кг", until: "ср 10 окт", daysLeft: 6, status: "Осталось на 6 дней" },
    { id: "drops", icon: "water_drop", name: "Капли Вет", perDay: "0,5 мл в день", left: "6,5", unit: "мл", until: "чт 11 окт", daysLeft: 13, status: "Курс кончится раньше — не покупать" }
  ]);
  const [qty, setQty] = React.useState(50);
  const [month, setMonth] = React.useState("март");
  const [toast, setToast] = React.useState(null);
  const done = () => { setItems((xs) => xs.map((x) => x.id === buy.id ? { ...x, left: buy.id === "levo" ? String(4 + qty) : "2,8", daysLeft: 14, until: "ещё 30+ дней", status: "Годен до " + month + " 2028" } : x)); setToast("Запас обновлён у всей семьи"); setBuy(null); };
  React.useEffect(() => { if (!toast) return; const t = setTimeout(() => setToast(null), 3000); return () => clearTimeout(t); }, [toast]);
  const chip = (on) => ({ minHeight: 44, padding: "0 16px", border: 0, borderRadius: 999, background: on ? "var(--accent-subtle)" : "var(--fill-2)", color: on ? "var(--accent-subtle-text)" : "var(--text-primary)", fontWeight: on ? 600 : 400, fontSize: "var(--fs-subheadline)", fontFamily: "inherit", cursor: "pointer" });
  return (
    <div style={{ position: "relative", height: "100%", display: "flex", flexDirection: "column", gap: 12, padding: "4px 20px 0", overflowY: "auto", scrollbarWidth: "none" }}>
      <span style={{ fontFamily: "var(--font-rounded)", fontWeight: 300, fontSize: "var(--fs-large-title)", padding: "8px 4px 0" }}>Запас</span>
      {items.sort((a, b) => a.daysLeft - b.daysLeft).map((m) => <StockCard key={m.id} {...m} onBought={() => setBuy(m)} />)}
      {toast && <div style={{ position: "sticky", bottom: 12 }}><Toast tone="info" text={toast} /></div>}
      {buy && <div style={{ position: "absolute", inset: 0, zIndex: 5 }}>
        <div onClick={() => setBuy(null)} style={{ position: "absolute", inset: 0, background: "var(--scrim)" }} />
        <div style={{ position: "absolute", left: 8, right: 8, bottom: 8, borderRadius: "var(--radius-sheet-floating)", background: "var(--glass-regular)", backdropFilter: "blur(var(--blur-glass)) saturate(var(--glass-saturate))", WebkitBackdropFilter: "blur(var(--blur-glass)) saturate(var(--glass-saturate))", boxShadow: "var(--glass-shadow)", padding: "8px 16px 24px", display: "flex", flexDirection: "column", gap: 16 }}>
          <span style={{ alignSelf: "center", width: 36, height: 5, borderRadius: 3, background: "var(--separator)" }} />
          <div style={{ display: "flex", flexDirection: "column", alignItems: "center" }}><span style={{ fontSize: "var(--fs-headline)", fontWeight: 600 }}>Купил {buy.name}</span><span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>запас обновится у всей семьи</span></div>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", minHeight: 64, padding: "0 8px", borderRadius: "var(--radius-row)", background: "var(--fill-1)" }}><Button size="m" variant="secondary" icon="remove" label="Меньше" onClick={() => setQty((q) => Math.max(1, q - 10))} /><span style={{ fontFamily: "var(--font-rounded)", fontWeight: 300, fontSize: 30 }}>{qty}<span style={{ fontSize: 13, color: "var(--accent-text)" }}>{buy.unit}</span></span><Button size="m" variant="secondary" icon="add" label="Больше" onClick={() => setQty((q) => q + 10)} /></div>
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}><span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>Годен до · с упаковки, можно пропустить</span><div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>{["январь", "февраль", "март", "апрель"].map((m) => <button key={m} onClick={() => setMonth(m)} style={chip(month === m)}>{m}</button>)}<button style={chip(false)}>2028</button></div><span style={{ display: "flex", alignItems: "center", gap: 6, fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}><Icon name="notifications" size={16} />Напомню за месяц до конца срока</span></div>
          <Button size="xl" edge fullWidth icon="add_shopping_cart" onClick={done}>Добавить в запас</Button>
        </div>
      </div>}
    </div>
  );
}
Object.assign(window, { StockScreen });
