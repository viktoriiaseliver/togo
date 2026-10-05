// Загружает компоненты для карточек превью: сначала _ds_bundle.js, иначе собирает .jsx на лету через Babel.
(function () {
  const ROOT = document.currentScript.src.replace(/components\/preview-loader\.js.*$/, "");
  const FILES = ["atoms/Icon", "atoms/Button", "atoms/IconButton", "atoms/Toggle", "atoms/SelectCircle", "atoms/Badge", "atoms/TextField", "atoms/ProgressBar", "atoms/Skeleton",
    "molecules/Card", "molecules/CardHeader", "molecules/StatusChip", "molecules/Metric", "molecules/ListRow", "molecules/SegmentedControl", "molecules/Stepper", "molecules/SlideAction", "molecules/Toast", "molecules/SearchField", "molecules/ActionRow", "molecules/ChoiceChips", "molecules/SectionHeader",
    "organisms/FitHeader", "organisms/DeviceCard", "organisms/NavBar", "organisms/TabBar", "organisms/EditBar", "organisms/Sheet", "organisms/ConfirmDialog", "organisms/EmptyState",
    "togo/QuickLog", "togo/VerdictCard", "togo/WalkBar", "togo/DoseCard", "togo/FastingWindow", "togo/MergeCard", "togo/EmergencyCard", "togo/DiaryEntry", "togo/TrainingTimer", "togo/MorningBrief", "togo/DogSwitcher", "togo/ProCard",
    "feedback/Alert", "feedback/InlineAlert", "feedback/PushNotification", "feedback/ContextMenu",
    "pickers/Calendar", "pickers/WeekStrip", "pickers/TimeField", "pickers/DateRow",
    "data/Timeline", "data/WeekChart",
    "togo-live/EscalationLadder", "togo-live/EpisodeCard", "togo-live/TripCard", "togo-live/WidgetPreview", "togo-live/LiveActivity",
    "togo-today/HeroReading", "togo-today/FactList", "togo-today/RecordTile", "togo-today/StockMeter", "togo-today/DayScale", "togo-today/ReadOnlyBar",
    "togo-flows/OnboardingStep", "togo-flows/PermissionCard", "togo-flows/ReminderSchedule", "togo-flows/ExportCard", "togo-flows/InviteCard",
    "inputs/TextArea", "inputs/Menu", "inputs/Slider", "media/Avatar", "media/MediaCell", "states/ListSkeleton", "states/SyncStatus",
    "togo-health/SkillMatrix", "togo-health/LabChart", "togo-health/TreatmentPlan", "togo-health/DogProfile", "togo-health/FamilyList", "togo-final/ReadingCard", "togo-final/FeedRow", "togo-final/StockCard", "togo-final/SwipeRow"];
  const findNS = () => {
    if (window.Graphite) return window.Graphite;
    for (const k of Object.keys(window)) {
      if (/^\d+$/.test(k)) continue;
      try { const o = window[k]; if (o && typeof o === "object" && o !== window && o.Button && o.Toggle && o.ListRow) return o; } catch (e) {}
    }
  };
  async function build() {
    const srcs = await Promise.all(FILES.map((f) => fetch(ROOT + "components/" + f + ".jsx").then((r) => r.text())));
    const names = [];
    let code = srcs.map((s) => {
      const own = [];
      const body = s.replace(/^import .*$/gm, "").replace(/export function (\w+)/g, (_, n) => { own.push(n); names.push(n); return "function " + n; });
      return "const {" + own.join(",") + "} = (function(){\n" + body + "\nreturn {" + own.join(",") + "};})();";
    }).join("\n");
    code = Babel.transform(code, { presets: ["react"] }).code;
    return new Function("React", code + "\nreturn {" + names.join(",") + "};")(React);
  }
  window.loadGraphite = async function () {
    if (findNS()) return findNS();
    try {
      await new Promise((ok, no) => { const s = document.createElement("script"); s.src = ROOT + "_ds_bundle.js"; s.onload = ok; s.onerror = no; document.head.appendChild(s); });
      if (findNS()) return findNS();
    } catch (e) {}
    return (window.Graphite = await build());
  };
})();
