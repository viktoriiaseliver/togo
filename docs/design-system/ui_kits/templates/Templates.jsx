// Универсальные шаблоны: Главная, Список, Деталь, Настройки. Контент — из presets.js, вид — только из компонентов Graphite.
const plural = (n, [one, few, many]) => { const m10 = n % 10, m100 = n % 100; return m10 === 1 && m100 !== 11 ? one : m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) ? few : many; };
const Stack = ({ gap = "var(--gap-cards)", children }) => <div style={{ display: "flex", flexDirection: "column", gap }}>{children}</div>;
const Grid = ({ min = 140, children }) => <div style={{ display: "grid", gridTemplateColumns: `repeat(auto-fit, minmax(min(100%, max(${min}px, calc(var(--fs-body) * ${min / 17}))), 1fr))`, gap: "var(--gap-cards)" }}>{children}</div>;
const Scroll = ({ pad, children }) => <div style={{ position: "absolute", inset: 0, overflowY: "auto", padding: `var(--space-8) ${pad}px 120px`, display: "flex", flexDirection: "column", gap: "var(--gap-sections)" }}>{children}</div>;

function StateBlock({ state, empty, onRetry, children }) {
  const G = window.Graphite;
  if (state === "loading") return <G.ListSkeleton rows={4} />;
  if (state === "empty") return <G.EmptyState card icon={empty.icon} title={empty.title} message={empty.message} actionLabel={empty.action} actionIcon="add" primary />;
  if (state === "error") return <Stack><G.InlineAlert tone="error" title="Не загрузилось" message="Проверь сеть. Сохранённое на телефоне не пропало." actionLabel="Повторить" onAction={onRetry} />{children}</Stack>;
  return children;
}

function HomeScreen({ P, pad, state, go, toast }) {
  const G = window.Graphite, H = P.home;
  return (
    <Scroll pad={pad}>
      <G.NavBar title={H.title} trailing={state === "offline" ? <G.SyncStatus state="offline" /> : <G.Button icon="add" label="Добавить" variant="surface" size="m" />} />
      {state === "loading" ? <G.ListSkeleton rows={2} /> : <G.Card>
        <G.CardHeader icon={H.hero.icon} tone="accent" kicker={H.hero.kicker} title={H.hero.title} />
        <G.Metric value={state === "empty" ? null : H.hero.value} unit={H.hero.unit} caption={state === "empty" ? "Данных пока нет" : H.hero.caption} size="l" />
        <G.ActionRow><G.Button onClick={() => toast(H.hero.primary + " · готово")}>{H.hero.primary}</G.Button><G.Button variant="secondary">{H.hero.secondary}</G.Button></G.ActionRow>
      </G.Card>}
      <Grid min={72}>{H.quick.map((q) => <G.Button key={q.label} variant="surface" size="xl" icon={q.icon} onClick={() => toast(q.label + " · записано")} style={{ flexDirection: "column", minHeight: 88, borderRadius: "var(--radius-row)", gap: "var(--space-4)" }}>{q.label}</G.Button>)}</Grid>
      <Grid>{H.tiles.map((t) => <G.Card key={t.title} gap={8}>
        <span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>{t.title}</span>
        <G.Metric value={state === "empty" ? null : t.value} unit={t.unit} size="m" />
        <span style={{ fontSize: "var(--fs-footnote)", color: t.tone === "warning" ? "var(--status-warning)" : "var(--text-secondary)" }}>{t.caption}</span>
      </G.Card>)}</Grid>
      <Stack><G.SectionHeader title={H.recentTitle} action="Все" onAction={() => go("list")} />
        <StateBlock state={state} empty={P.list.empty}>{H.recent.map((r) => <G.ListRow key={r.title} icon={r.icon} title={r.title} subtitle={r.subtitle} chevron onClick={() => go("detail", r)} />)}</StateBlock>
      </Stack>
    </Scroll>
  );
}

function ListScreen({ P, pad, state, go, toast, setState }) {
  const G = window.Graphite, Li = P.list;
  const [items, setItems] = React.useState(Li.items);
  const [q, setQ] = React.useState(""); const [f, setF] = React.useState(Li.filters[0]);
  const [edit, setEdit] = React.useState(false); const [sel, setSel] = React.useState([]); const [ask, setAsk] = React.useState(false);
  React.useEffect(() => { setItems(Li.items); setF(Li.filters[0]); setSel([]); setEdit(false); }, [P]);
  const shown = items.filter((i) => (f === Li.filters[0] || i.group === f) && i.title.toLowerCase().includes(q.toLowerCase()));
  const toggle = (id) => setSel((s) => (s.includes(id) ? s.filter((x) => x !== id) : [...s, id]));
  const del = () => { const keep = items; setItems(items.filter((i) => !sel.includes(i.id))); toast(sel.length === 1 ? P.nounDone : "Удалено: " + sel.length, () => setItems(keep)); setSel([]); setEdit(false); setAsk(false); };
  return (
    <>
      <Scroll pad={pad}>
        <G.NavBar title={Li.title} editTitle={edit ? (sel.length ? "Выбрано: " + sel.length : "Выбери") : undefined}
          leading={edit ? <G.Button variant="plain" onClick={() => setSel(sel.length === shown.length ? [] : shown.map((i) => i.id))}>{sel.length === shown.length ? "Снять" : "Все"}</G.Button> : null}
          trailing={<G.Button variant="plain" disabled={state !== "data" && state !== "offline"} onClick={() => { setEdit(!edit); setSel([]); }}>{edit ? "Готово" : "Изменить"}</G.Button>} />
        <Stack gap="var(--space-12)">
          <G.SearchField value={q} onChange={setQ} placeholder={Li.search} onCancel={() => setQ("")} />
          <G.ChoiceChips options={Li.filters} value={f} onChange={setF} />
          {state === "offline" && <G.SyncStatus state="offline" detail={"2 " + plural(2, P.noun) + " ждут сети"} />}
        </Stack>
        <StateBlock state={state} empty={Li.empty} onRetry={() => setState("data")}>
          <Stack>
            {shown.length === 0 ? <G.EmptyState icon="search_off" title="Ничего не нашлось" message={"Нет совпадений с «" + q + "»"} actionLabel="Сбросить" onAction={() => { setQ(""); setF(Li.filters[0]); }} />
              : shown.map((i) => <G.ListRow key={i.id} icon={i.icon} iconTone={i.tone === "error" ? "error" : undefined} title={i.title} subtitle={i.subtitle} value={edit ? undefined : i.value}
                  leading={edit ? <G.SelectCircle checked={sel.includes(i.id)} onChange={() => toggle(i.id)} /> : null} chevron={!edit}
                  onClick={() => (edit ? toggle(i.id) : go("detail", i))} style={sel.includes(i.id) ? { background: "var(--fill-selected)" } : null} />)}
          </Stack>
        </StateBlock>
      </Scroll>
      {edit && sel.length > 0 && <G.EditBar count={sel.length} onDelete={() => setAsk(true)} style={{ position: "absolute", left: pad, right: pad, bottom: 24, zIndex: 3 }} />}
      <G.ConfirmDialog open={ask} message={"Удалить " + sel.length + " " + plural(sel.length, P.noun) + "? Отменить можно 5 секунд."} confirmLabel={"Удалить " + sel.length} onConfirm={del} onCancel={() => setAsk(false)} />
    </>
  );
}

function DetailScreen({ P, pad, item, back, toast }) {
  const G = window.Graphite, D = P.detail;
  const [note, setNote] = React.useState("");
  return (
    <Scroll pad={pad}>
      <G.NavBar title={item.title} onBack={back} trailing={<G.Button icon="more_horiz" label="Ещё" variant="surface" size="m" />} />
      <G.Card>
        <G.CardHeader icon={item.icon} tone={item.tone === "error" ? "error" : "accent"} title={item.title} subtitle={item.subtitle} />
        <Grid min={120}>{D.metrics.map((m) => <div key={m.caption} style={{ background: "var(--fill-2)", borderRadius: "var(--radius-inner)", padding: "var(--pad-inner)" }}><G.Metric value={m.value} unit={m.unit} caption={m.caption} size="m" /></div>)}</Grid>
        <G.ActionRow><G.Button onClick={() => toast(D.primary + " · готово")}>{D.primary}</G.Button><G.Button variant="secondary">{D.secondary}</G.Button></G.ActionRow>
      </G.Card>
      <Stack><G.SectionHeader title={D.timelineTitle} /><G.Timeline items={D.timeline} /></Stack>
      <G.TextArea label={D.note} value={note} onChange={setNote} max={200} placeholder="Необязательно" />
    </Scroll>
  );
}

function SettingsScreen({ P, pad, toast }) {
  const G = window.Graphite, S = P.settings;
  const [tg, setTg] = React.useState(S.toggles.map((t) => t.on)); const [m, setM] = React.useState(S.menu.value); const [s, setS] = React.useState(S.slider.value);
  React.useEffect(() => { setTg(S.toggles.map((t) => t.on)); setM(S.menu.value); setS(S.slider.value); }, [P]);
  return (
    <Scroll pad={pad}>
      <G.NavBar title={P.tabs[2].label} />
      <G.Card style={{ alignItems: "center", textAlign: "center" }}>
        <G.Avatar name={S.profile.name} icon={S.profile.icon} size="xl" />
        <Stack gap="var(--space-4)"><span style={{ fontSize: "var(--fs-title-2)", lineHeight: 1.2 }}>{S.profile.name}</span><span style={{ fontSize: "var(--fs-subheadline)", color: "var(--text-secondary)" }}>{S.profile.sub}</span></Stack>
        <G.Button variant="secondary" size="m" icon="edit">Изменить</G.Button>
      </G.Card>
      <Stack><G.SectionHeader title="Основное" />
        {S.toggles.map((t, i) => <G.ListRow key={t.title} icon={t.icon} title={t.title} subtitle={t.subtitle} trailing={<G.Toggle checked={tg[i]} label={t.title} onChange={(v) => setTg(tg.map((x, j) => (j === i ? v : x)))} />} />)}
        <G.Menu label={S.menu.label} value={m} onChange={setM} options={S.menu.options} />
        <G.DateRow label={S.date.label} value={S.date.value} />
        <div style={{ background: "var(--fill-1)", borderRadius: "var(--radius-row)", padding: "var(--pad-row-y) var(--pad-row)", boxShadow: "var(--elev-1)" }}><G.Slider label={S.slider.label} value={s} min={S.slider.min} max={S.slider.max} onChange={setS} format={(v) => v + S.slider.unit} /></div>
      </Stack>
      <Stack><G.SectionHeader title="Данные" />
        <G.ListRow icon="ios_share" title="Экспорт" subtitle="PDF и CSV" chevron onClick={() => {}} />
        <G.ListRow destructive title={S.danger} onClick={() => toast("Нужно подтверждение")} />
      </Stack>
    </Scroll>
  );
}

function TemplateApp({ presetKey, width, state, setState }) {
  const G = window.Graphite, P = window.PRESETS[presetKey];
  const [tab, setTab] = React.useState("home"); const [item, setItem] = React.useState(null); const [t, setT] = React.useState(null);
  const pad = width < 375 ? 16 : 20;
  React.useEffect(() => { setItem(null); }, [presetKey]);
  const toast = (text, undo) => { setT({ text, undo, k: Date.now() }); };
  React.useEffect(() => { if (!t) return; const i = setTimeout(() => setT(null), 5000); return () => clearTimeout(i); }, [t]);
  const go = (to, it) => { if (to === "detail") setItem(it); else { setItem(null); setTab(to); } };
  const props = { P, pad, state, go, toast, setState };
  return (
    <>
      {item ? <DetailScreen {...props} item={item} back={() => setItem(null)} />
        : tab === "home" ? <HomeScreen {...props} /> : tab === "list" ? <ListScreen {...props} /> : <SettingsScreen {...props} />}
      {t && <G.Toast key={t.k} tone={t.undo ? "undo" : "info"} text={t.text} actionLabel={t.undo ? "Отменить" : undefined} onAction={() => { t.undo && t.undo(); setT(null); }} style={{ position: "absolute", left: pad, right: pad, bottom: 100, zIndex: 4 }} />}
      {!item && <G.TabBar value={tab} onChange={(v) => { setTab(v); }} items={P.tabs} compact={width < 375} style={{ position: "absolute", left: pad, right: pad, bottom: 24, zIndex: 2 }} />}
    </>
  );
}
window.TemplateApp = TemplateApp;
