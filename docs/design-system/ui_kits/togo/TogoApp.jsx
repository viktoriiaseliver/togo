// Togo — кликабельный прототип на компонентах Graphite. Контент демонстрационный.
const pad2 = (n) => String(n).padStart(2, "0");
const nowHM = () => { const d = new Date(); return pad2(d.getHours()) + ":" + pad2(d.getMinutes()); };
const HOW = ["У двери", "Скулил", "Подошёл ко мне", "Не просил"];
const STOOL = ["Нормальный", "Мягкий", "Жидкий", "Кровь"];

const Chips = (p) => <window.Graphite.ChoiceChips {...p} />;
const Section = ({ title, action, onAction, children }) => <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-8)" }}><window.Graphite.SectionHeader title={title} action={action} onAction={onAction} />{children}</div>;

function TodayScreen({ pad, log, addEntry, walk, setWalk, dose, setDose, fasting, toast }) {
  const G = window.Graphite;
  const [sheet, setSheet] = React.useState(null);
  const [pick, setPick] = React.useState(null);
  const [merge, setMerge] = React.useState(true);
  const [brief, setBrief] = React.useState(true);
  const [trip, setTrip] = React.useState([{ label: "Левотироксин на 8 дней" }, { label: "Ветпаспорт", done: true }, { label: "Корм на дорогу" }]);
  const [sec, setSec] = React.useState(0);
  const [noMarks, setNoMarks] = React.useState(false);
  const [episode, setEpisode] = React.useState(null);
  React.useEffect(() => { if (!walk) return; const t = setInterval(() => setSec((s) => s + 1), 1000); return () => clearInterval(t); }, [walk]);
  const last = (k) => log.find((e) => e.kind === k && !e.deleted);
  const since = (e) => (e ? "в " + e.time : "нет записей");
  const open = (k) => { if (k === "food" && fasting) { setSheet("fast"); return; } setPick(null); setSheet(k); };
  const save = () => { const t = { out: ["pets", "Выход", pick ? "Как попросил: " + pick.toLowerCase() : ""], stool: ["eco", "Стул", pick || ""], food: ["restaurant", "Корм", ""], fast: ["restaurant", "Корм", "В окно натощак"] }[sheet];
    addEntry({ kind: sheet === "fast" ? "food" : sheet, icon: t[0], title: t[1], detail: t[2], tone: pick === "Кровь" ? "overdue" : undefined }); setSheet(null);
    if (sheet === "stool" && (pick === "Жидкий" || pick === "Кровь")) setEpisode((e) => ({ started: e ? e.started : nowHM(), count: (e ? e.count : 0) + 1, title: pick === "Кровь" ? "Кровь в стуле" : "Жидкий стул" })); };
  const tryFinish = () => { const m = walk.marks; if (!m.pee && !m.poo) setNoMarks(true); else finish(); };
  const finish = () => { setNoMarks(false); const m = walk.marks; const n = [m.pee && "пописал", m.poo && "покакал"].filter(Boolean);
    addEntry({ kind: "out", icon: "pets", title: "Прогулка " + Math.max(1, Math.round(sec / 60)) + " мин", detail: n.length ? n.join(", ") : "без отметок" }); setWalk(null); setSec(0); };
  return (
    <>
      <div style={{ position: "absolute", inset: 0, overflowY: "auto", padding: `8px ${pad}px 120px`, display: "flex", flexDirection: "column", gap: "var(--space-20)" }}>
        <G.NavBar title="Сегодня" />
        {brief && <G.MorningBrief items={["Ночью мама выводила в 03:10, всё сделал", "Корм заканчивается через 4 дня", "Вчера вечером доза пропущена"]} onDismiss={() => setBrief(false)} />}
        {walk
          ? <G.WalkBar elapsed={pad2(Math.floor(sec / 60)) + ":" + pad2(sec % 60)} marks={[{ value: "pee", label: "Пописал", count: walk.marks.pee }, { value: "poo", label: "Покакал", count: walk.marks.poo }]}
              onMark={(v) => setWalk({ marks: { ...walk.marks, [v]: (walk.marks[v] || 0) + 1 } })} onFinish={tryFinish} />
          : <G.VerdictCard outcome="likely" reason={"Последний выход " + since(last("out")) + ", обычно раз в 3 ч"} onWalkOut={() => setWalk({ marks: {} })} onLater={() => {}} />}
        {episode && <G.EpisodeCard title={episode.title} started={episode.started} count={episode.count} signs={["Ест", "Пьёт", "Активный"]} onAdd={() => setEpisode({ ...episode, count: episode.count + 1 })} onCall={() => {}} onEnd={() => { setEpisode(null); toast("Эпизод закрыт"); }} />}
        <G.QuickLog onLog={open} items={[{ value: "out", label: "Выход", icon: "pets", since: since(last("out")) }, { value: "food", label: "Корм", icon: "restaurant", since: since(last("food")) }, { value: "stool", label: "Стул", icon: "eco", since: since(last("stool")) }]} />
        <Section title="Лечение">
          {fasting && <G.FastingWindow phase="after" minutesLeft={25} progress={0.4} until="07:40" />}
          <G.DoseCard state={dose ? "taken" : "due"} name="Левотироксин" dose="200 мкг · 1 таблетка" time={dose || "07:00"} note={dose ? "Уже дал в " + dose + " — вторую не запишу" : undefined}
            onGive={() => { const t = nowHM(); setDose(t); addEntry({ kind: "dose", icon: "medication", title: "Доза", detail: "Левотироксин 200 мкг", tone: "done" }); }} onUndo={() => setDose(null)} />
        </Section>
        <G.TripCard place="Лион" dates="12–19 окт" daysLeft={5} checklist={trip} onToggle={(i) => setTrip(trip.map((x, j) => (j === i ? { ...x, done: !x.done } : x)))} />
        <G.InlineAlert tone="warning" title="Уведомления выключены" message="Без них доза по часам не напомнит" actionLabel="Открыть настройки" />
        {merge && <G.MergeCard first={{ what: "Выход", who: "Ты", time: "08:10" }} second={{ what: "Выход", who: "Мама", time: "08:18" }} onMerge={() => { setMerge(false); toast("Записи объединены"); }} onKeep={() => setMerge(false)} />}
      </div>
      <G.Sheet open={sheet === "out" || sheet === "stool"} title={sheet === "out" ? "Выход" : "Стул"} onCancel={() => setSheet(null)} onDone={save} style={{ padding: `8px ${pad}px 32px` }}>
        <span style={{ fontSize: "var(--fs-subheadline)", color: "var(--text-secondary)" }}>{sheet === "out" ? "Как попросил?" : "Какой?"}</span>
        <Chips options={sheet === "out" ? HOW : STOOL} value={pick} onChange={setPick} />
        <G.Button fullWidth onClick={save}>Записать</G.Button>
      </G.Sheet>
      <G.Sheet open={sheet === "food"} title="Корм" onCancel={() => setSheet(null)} onDone={save} style={{ padding: `8px ${pad}px 32px` }}>
        <G.Button fullWidth onClick={save}>Записать корм в {nowHM()}</G.Button>
      </G.Sheet>
      <G.Sheet open={sheet === "fast"} title="Окно натощак" onCancel={() => setSheet(null)} onDone={() => setSheet(null)} style={{ padding: `8px ${pad}px 32px` }}>
        <G.FastingWindow phase="after" minutesLeft={25} progress={0.4} until="07:40" />
        <span style={{ fontSize: "var(--fs-subheadline)", lineHeight: 1.4, color: "var(--text-secondary)" }}>Таблетка всасывается хуже, если покормить раньше. Подожди 25 минут.</span>
        <G.Button fullWidth onClick={() => setSheet(null)}>Подожду</G.Button>
        <G.Button fullWidth variant="secondary" onClick={save}>Всё равно записать</G.Button>
      </G.Sheet>
      <G.Alert open={noMarks} title="Закончить прогулку?" message="Ты не отметил ни одного дела. Запись сохранится без отметок." actions={[{ label: "Продолжить", style: "cancel", onPress: () => setNoMarks(false) }, { label: "Закончить", onPress: finish }]} />
    </>
  );
}

const MONTHS = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"];
const dkey = (x) => x.getFullYear() + "-" + pad2(x.getMonth() + 1) + "-" + pad2(x.getDate());
function HistoryScreen({ pad, log, remove, retime }) {
  const G = window.Graphite;
  const today = React.useMemo(() => new Date(), []);
  const [day, setDay] = React.useState(today);
  const [cal, setCal] = React.useState(false);
  const [edit, setEdit] = React.useState(null);
  const [view, setView] = React.useState("day");
  const marks = React.useMemo(() => { const m = {}; for (let i = 0; i < 20; i++) { const x = new Date(today); x.setDate(today.getDate() - i); m[dkey(x)] = i === 2 ? "overdue" : "done"; } return m; }, [today]);
  const isToday = day.toDateString() === today.toDateString();
  const items = isToday
    ? [{ type: "now", time: nowHM() }, ...log.flatMap((e, i) => { const r = { ...e, onClick: e.deleted ? undefined : () => setEdit({ id: e.id, time: e.time }) }; return i === 0 && e.kind !== "out" ? [{ type: "gap", label: "С последнего выхода больше 3 ч", warn: true }, r] : [r]; })]
    : [{ time: "21:30", icon: "pets", title: "Выход", detail: "Как попросил: скулил" }, { time: "19:00", icon: "medication", title: "Доза пропущена", tone: "overdue" }, { type: "gap", label: "5 ч без выхода", warn: true }, { time: "13:40", icon: "pets", title: "Выход", who: "Мама" }, { time: "08:00", icon: "restaurant", title: "Корм" }];
  const now = today.getHours() * 60 + today.getMinutes();
  return (
    <>
      <div style={{ position: "absolute", inset: 0, overflowY: "auto", padding: `8px ${pad}px 120px`, display: "flex", flexDirection: "column", gap: "var(--space-16)" }}>
        <G.NavBar title="История" trailing={<G.IconButton icon="calendar_month" label="Календарь" size="m" onClick={() => setCal(true)} />} />
        <G.SegmentedControl value={view} onChange={setView} options={[{ value: "day", label: "День" }, { value: "week", label: "Неделя" }]} />
        {view === "day" ? <>
          <G.WeekStrip value={day} onChange={setDay} today={today} marks={marks} />
          <G.SectionHeader title={isToday ? "Сегодня" : day.getDate() + " " + MONTHS[day.getMonth()]} />
          <G.Timeline items={items} />
          <span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)", textAlign: "center" }}>Тап по записи — изменить время или удалить.</span>
        </> : <>
          <G.SectionHeader title="Выходов в день" />
          <G.WeekChart unit="выходов" target={5} data={[{ label: "пн", value: 5 }, { label: "вт", value: 6 }, { label: "ср", value: null }, { label: "чт", value: 4 }, { label: "пт", value: 5 }, { label: "сб", value: 7 }, { label: "вс", value: log.filter((e) => e.kind === "out" && !e.deleted).length, active: true }]} />
          <G.InlineAlert title="В среду нет записей" message="Без них вердикт на следующей неделе будет менее точным" />
          <G.Button fullWidth variant="secondary" icon="description">Отчёт врачу за неделю</G.Button>
        </>}
      </div>
      <G.Sheet open={cal} title="Выбрать день" onCancel={() => setCal(false)} onDone={() => setCal(false)} style={{ padding: `8px ${pad}px 32px` }}>
        <G.Calendar value={day} onChange={(d) => { setDay(d); setCal(false); }} max={today} today={today} marks={marks} style={{ boxShadow: "none", background: "var(--fill-2)" }} />
      </G.Sheet>
      <G.Sheet open={!!edit} title="Запись" onCancel={() => setEdit(null)} onDone={() => { retime(edit.id, edit.time); setEdit(null); }} style={{ padding: `8px ${pad}px 32px` }}>
        {edit && <G.TimeField value={edit.time} onChange={(t) => setEdit({ ...edit, time: t })} quick={[{ label: "Сейчас", minutes: now }, { label: "15 мин назад", minutes: now - 15 }, { label: "30 мин назад", minutes: now - 30 }]} />}
        <G.Button fullWidth variant="destructive" icon="delete" onClick={() => { remove(edit.id); setEdit(null); }}>Удалить запись</G.Button>
      </G.Sheet>
    </>
  );
}

function DogScreen({ pad, toast }) {
  const G = window.Graphite;
  const [train, setTrain] = React.useState(null);
  const [tsec, setTsec] = React.useState(0);
  const t0 = React.useRef(0);
  React.useEffect(() => { if (!train) return; const i = setInterval(() => setTsec((s) => s + 1), 1000); return () => clearInterval(i); }, [!!train]);
  return (
    <div style={{ position: "absolute", inset: 0, overflowY: "auto", padding: `8px ${pad}px 120px`, display: "flex", flexDirection: "column", gap: "var(--space-20)" }}>
      <G.NavBar title="Стич" trailing={<G.IconButton icon="settings" label="Настройки" size="m" />} />
      <G.DogSwitcher dogs={[{ id: "s", name: "Стич" }]} value="s" onAdd={() => toast("Вторая собака — в Togo Pro")} />
      <Section title="Занятие">
        {train
          ? <G.TrainingTimer skill="Место" elapsed={pad2(Math.floor(tsec / 60)) + ":" + pad2(tsec % 60)} overLimit={tsec >= 180} reps={train.reps} lastDelayMs={train.delay}
              onMarker={() => setTrain({ reps: train.reps + 1, delay: 300 + Math.round(Math.random() * 1200) })} onFinish={() => { setTrain(null); setTsec(0); toast("Занятие записано"); }} />
          : <G.ListRow icon="school" title="Начать занятие" subtitle="Место · вчера 6 повторов" chevron onClick={() => setTrain({ reps: 0 })} />}
      </Section>
      <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-8)" }}>
        <G.ListRow icon="pets" title="Шипперке" subtitle="3 года 6 месяцев" chevron />
        <G.ListRow icon="medication" title="Лечение" subtitle="Левотироксин · утром натощак" chevron />
      </div>
      <Section title="Виджеты и экран блокировки">
        <div style={{ display: "flex", flexWrap: "wrap", gap: "var(--space-12)" }}><G.WidgetPreview since="2 ч 10" verdict="Похоже на нужду" /><G.LiveActivity island elapsed="12:40" /></div>
        <G.LiveActivity title="Прогулка" elapsed="12:40" detail="Пописал · 1" />
      </Section>
      <Section title="Если что-то случилось">
        <G.EmergencyCard vetName="Ветклиника" phone="+33 4 93 00 00 00" callNow={["Кровь в стуле или рвоте", "Не ест больше суток", "Вялый и не встаёт"]} watch={["Один мягкий стул", "Пропустил одну еду"]} onReport={() => {}} />
      </Section>
    </div>
  );
}

function FamilyScreen({ pad }) {
  const [pro, setPro] = React.useState(false);
  const G = window.Graphite;
  return (
    <div style={{ position: "absolute", inset: 0, overflowY: "auto", padding: `8px ${pad}px 120px`, display: "flex", flexDirection: "column", gap: "var(--space-20)" }}>
      <G.NavBar title="Семья" />
      <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-8)" }}>
        <G.ListRow icon="person" title="Ты" subtitle="Хозяйка" />
        <G.ListRow icon="person" title="Мама" subtitle="Дежурная сегодня" trailing={<G.Badge tone="accent">Дежурный</G.Badge>} />
      </div>
      <G.Button fullWidth icon="person_add" onClick={() => setPro(true)}>Пригласить человека</G.Button>
      {pro && <Section title="Третий человек в семье — в Pro"><G.ProCard price="2,99 € в месяц" onBuy={() => setPro(false)} onRestore={() => {}} /></Section>}
    </div>
  );
}

function HealthScreen({ pad, dose, setDose, toast }) {
  const G = window.Graphite;
  const [step, setStep] = React.useState(1);
  return (
    <div style={{ position: "absolute", inset: 0, overflowY: "auto", padding: `8px ${pad}px 120px`, display: "flex", flexDirection: "column", gap: "var(--space-20)" }}>
      <G.NavBar title="Здоровье" />
      <Section title="Дозы сегодня">
        <G.DoseCard state={dose ? "taken" : "due"} name="Левотироксин" dose="200 мкг" time={dose || "07:00"} />
        <G.DoseCard state="overdue" name="Левотироксин" dose="200 мкг" time="19:00" note="Вчера вечером: пропущена" />
      </Section>
      {step >= 0 && <Section title="Напоминание о дозе">
        <G.EscalationLadder current={step} steps={[{ who: "Ты", how: "Уведомление", time: "07:00" }, { who: "Ты", how: "Повтор, критическое", time: "07:15" }, { who: "Мама", how: "Дежурному", time: "07:30" }]} onAck={() => { setStep(-1); setDose && setDose(nowHM()); toast("Доза записана"); }} />
      </Section>}
      <Section title="Как выглядит уведомление">
        <G.PushNotification title="Доза Стичу" body="Левотироксин 200 мкг, 07:00. Потом 40 минут без еды." actions={[{ label: "Дал" }, { label: "Через 10 мин" }]} />
      </Section>
      <G.Button fullWidth variant="secondary" icon="description">Отчёт врачу</G.Button>
    </div>
  );
}

function TogoApp({ width }) {
  const G = window.Graphite;
  const [tab, setTab] = React.useState("today");
  const [walk, setWalk] = React.useState(null);
  const [dose, setDose] = React.useState(null);
  const [toastS, setToastS] = React.useState(null);
  const tt = React.useRef(); const nid = React.useRef(10);
  const [log, setLog] = React.useState([
    { id: 1, kind: "out", time: "08:10", icon: "pets", title: "Выход", detail: "Как попросил: у двери", who: "Мама" },
    { id: 2, kind: "food", time: "07:45", icon: "restaurant", title: "Корм", detail: "Завтрак" },
    { id: 3, kind: "stool", time: "06:50", icon: "eco", title: "Стул", detail: "Нормальный" },
  ]);
  const toast = (text, undo) => { clearTimeout(tt.current); setToastS({ text, undo }); tt.current = setTimeout(() => setToastS(null), 5000); };
  const addEntry = (e) => { const id = nid.current++; setLog((l) => [{ id, time: nowHM(), ...e }, ...l]); toast("Записано", () => setLog((l) => l.filter((x) => x.id !== id))); };
  const remove = (id) => { setLog((l) => l.map((x) => (x.id === id ? { ...x, deleted: true, detail: "Удалено" } : x))); const prev = log.find((x) => x.id === id);
    toast("Запись удалена", () => setLog((l) => l.map((x) => (x.id === id ? prev : x)))); };
  const retime = (id, time) => { setLog((l) => l.map((x) => (x.id === id ? { ...x, time } : x))); toast("Время изменено"); };
  const pad = width < 375 ? 16 : 20;
  const tabs = [{ value: "today", label: "Сегодня", icon: "today" }, { value: "dog", label: "Собака", icon: "pets" }, { value: "history", label: "История", icon: "history" }, { value: "family", label: "Семья", icon: "group" }, { value: "health", label: "Здоровье", icon: "medical_services" }];
  const props = { pad, log, addEntry, walk, setWalk, dose, setDose, fasting: !!dose, toast, remove, retime };
  return (
    <>
      {tab === "today" && <TodayScreen {...props} />}
      {tab === "history" && <HistoryScreen {...props} />}
      {tab === "dog" && <DogScreen {...props} />}
      {tab === "family" && <FamilyScreen {...props} />}
      {tab === "health" && <HealthScreen {...props} />}
      {toastS && <G.Toast text={toastS.text} actionLabel={toastS.undo ? "Отменить" : undefined} onAction={() => { clearTimeout(tt.current); setToastS(null); toastS.undo(); }} style={{ position: "absolute", left: 12, right: 12, bottom: 104 }} />}
      <G.TabBar value={tab} onChange={setTab} compact={width < 375} items={tabs} style={{ position: "absolute", left: 12, right: 12, bottom: 24 }} />
    </>
  );
}
window.TogoApp = TogoApp;
