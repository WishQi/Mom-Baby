(() => {
  "use strict";

  const STORAGE_KEY = "mom-baby-prototype-v4";
  const app = document.querySelector("#app");
  const board = document.querySelector("#board-root");
  const toastEl = document.querySelector("#toast");

  const iconPaths = {
    back: '<path d="m15 18-6-6 6-6"/><path d="M9 12h10"/>',
    chevron: '<path d="m9 18 6-6-6-6"/>',
    check: '<path d="m5 12 4 4L19 6"/>',
    lock: '<rect x="4" y="10" width="16" height="11" rx="3"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>',
    shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10Z"/><path d="m9 12 2 2 4-4"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    minus: '<path d="M5 12h14"/>',
    close: '<path d="m6 6 12 12M18 6 6 18"/>',
    more: '<circle cx="5" cy="12" r="1" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1" fill="currentColor" stroke="none"/><circle cx="19" cy="12" r="1" fill="currentColor" stroke="none"/>',
    home: '<path d="m3 11 9-8 9 8"/><path d="M5 10v10h14V10M9 20v-6h6v6"/>',
    history: '<path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5M12 7v5l3 2"/>',
    chart: '<path d="M4 19V5M4 19h16"/><path d="m7 15 4-5 3 2 5-7"/>',
    album: '<rect x="3" y="4" width="18" height="16" rx="3"/><circle cx="9" cy="9" r="2"/><path d="m4 17 5-5 4 3 3-3 5 5"/>',
    user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
    feed: '<path d="M7 4h10M9 4v4l-2 3v8a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2v-8l-2-3V4"/><path d="M8 13h8"/>',
    nursing: '<path d="M8 5c-2 1-3 3-3 6 0 5 3 8 7 8s7-3 7-8c0-3-1-5-3-6"/><path d="M9 10c0 2 1 4 3 4s3-2 3-4"/><path d="M10 5c0-2 4-2 4 0"/>',
    pump: '<path d="M8 3h8v5H8zM10 8v3l-3 3v7h10v-7l-3-3V8"/><path d="M7 16h10M17 11c3 0 4 2 4 4v4"/>',
    diaper: '<path d="M5 5c2 2 4 3 7 3s5-1 7-3v10c0 4-3 6-7 6s-7-2-7-6Z"/><path d="M5 11c2 2 4 3 7 3s5-1 7-3"/>',
    sleep: '<path d="M20 15.5A8.5 8.5 0 0 1 8.5 4 8.5 8.5 0 1 0 20 15.5Z"/><path d="m16 4 1 2 2 .5-2 1.5v2l-1.5-1-2 1 .5-2-1.5-1.5 2-.5Z"/>',
    bottle: '<path d="M9 3h6M10 3v4L8 9v10a2 2 0 0 0 2 2h4a2 2 0 0 0 2-2V9l-2-2V3"/><path d="M8 12h8"/>',
    can: '<ellipse cx="12" cy="5" rx="6" ry="2.5"/><path d="M6 5v14c0 1.4 12 1.4 12 0V5"/><path d="M6 12c0 1.4 12 1.4 12 0"/>',
    camera: '<path d="M4 7h4l2-3h4l2 3h4v13H4Z"/><circle cx="12" cy="13" r="4"/>',
    qr: '<path d="M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM15 14h2v2h-2zM18 14h2v5h-3M14 18h2v2h-2z"/>',
    tag: '<path d="M20 13 13 20 4 11V4h7Z"/><circle cx="8.5" cy="8.5" r="1.5"/>',
    pause: '<path d="M8 5v14M16 5v14"/>',
    play: '<path d="m8 5 11 7-11 7Z"/>',
    switch: '<path d="m17 3 4 4-4 4M3 7h18M7 21l-4-4 4-4M21 17H3"/>',
    stop: '<rect x="6" y="6" width="12" height="12" rx="2"/>',
    edit: '<path d="M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L8 18l-4 1 1-4Z"/>',
    calendar: '<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M8 3v4M16 3v4M3 10h18"/>',
    cloud: '<path d="M7 18h11a4 4 0 0 0 .5-8A7 7 0 0 0 5 11.5 3.5 3.5 0 0 0 7 18Z"/>',
    export: '<path d="M12 3v12M8 7l4-4 4 4"/><path d="M5 13v7h14v-7"/>',
    settings: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1-2.8 2.8-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.6v.2h-4V21a1.7 1.7 0 0 0-1-1.6 1.7 1.7 0 0 0-1.9.3l-.1.1L4.2 17l.1-.1a1.7 1.7 0 0 0 .3-1.9A1.7 1.7 0 0 0 3 14H2.8v-4H3a1.7 1.7 0 0 0 1.6-1 1.7 1.7 0 0 0-.3-1.9L4.2 7 7 4.2l.1.1a1.7 1.7 0 0 0 1.9.3A1.7 1.7 0 0 0 10 3V2.8h4V3a1.7 1.7 0 0 0 1 1.6 1.7 1.7 0 0 0 1.9-.3l.1-.1L19.8 7l-.1.1a1.7 1.7 0 0 0-.3 1.9 1.7 1.7 0 0 0 1.6 1h.2v4H21a1.7 1.7 0 0 0-1.6 1Z"/>',
    box: '<path d="m4 7 8-4 8 4-8 4Z"/><path d="M4 7v10l8 4 8-4V7M12 11v10"/>',
    heart: '<path d="M20.8 4.6a5.4 5.4 0 0 0-7.6 0L12 5.8l-1.2-1.2a5.4 5.4 0 0 0-7.6 7.6L12 21l8.8-8.8a5.4 5.4 0 0 0 0-7.6Z"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/>',
    image: '<rect x="3" y="4" width="18" height="16" rx="3"/><circle cx="9" cy="10" r="2"/><path d="m4 18 5-5 4 3 3-3 5 5"/>',
    bell: '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/>',
    trash: '<path d="M4 7h16M9 7V4h6v3M7 7l1 14h8l1-14M10 11v6M14 11v6"/>',
    milk: '<path d="M12 3c3 4 6 7 6 11a6 6 0 1 1-12 0c0-4 3-7 6-11Z"/>',
    photoAdd: '<rect x="3" y="5" width="18" height="15" rx="3"/><path d="m4 18 5-5 4 3 3-3 5 5M12 3v6M9 6h6"/>'
  };

  function icon(name, className = "") {
    return `<svg class="${className}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${iconPaths[name] || iconPaths.info}</svg>`;
  }

  function initialState() {
    const sampleCanSnapshot = { id: "can_example_archived", brand: "星禾初护（示例）", product: "婴儿配方奶粉 1 段（示例）", stage: "0–6 个月", lot: "CN260718A3", produced: "2026-07-18", expires: "2028-07-17", trace: "6930000123456 / X8F2", version: 1 };
    const sampleBottleSnapshot = { id: "bottle_example_daily", nickname: "小满的日用奶瓶", brand: "澄芽（示例）", model: "圆润系列 160 ml（示例）", code: "CY-160-0426", version: 1 };
    return {
      screen: "welcome",
      previous: "home",
      consentGuardian: false,
      consentChild: false,
      babyName: "小满",
      babyBirth: "2026-06-09",
      growthGroup: "女童",
      modules: { feeding: true, diaper: true, sleep: true, growth: true, album: true },
      nursing: { active: false, currentSide: "left", paused: false, leftBase: 0, rightBase: 0, tickAt: 0, endedAt: 0, startedAt: 0, segments: [] },
      pump: { active: false, mode: "double", singleSide: "left", leftBase: 0, rightBase: 0, leftTick: 0, rightTick: 0, leftStartedAt: 0, rightStartedAt: 0, leftEndedAt: 0, rightEndedAt: 0, leftEnded: false, rightEnded: false, leftVolume: 70, rightVolume: 65, volumeMode: "sides", startedAt: 0, endedAt: 0 },
      bottleFeed: { type: "formula", amount: 90, note: "" },
      formulaCan: null,
      formulaDraft: { brand: "星禾初护（示例）", product: "婴儿配方奶粉 1 段（示例）", stage: "0–6 个月", lot: "CN260718A3", produced: "2026-07-18", expires: "2028-07-17", trace: "6930000123456 / X8F2" },
      capture: { front: false, batch: false, code: false },
      bottle: null,
      bottleDraft: { nickname: "小满的日用奶瓶", brand: "澄芽（示例）", model: "圆润系列 160 ml（示例）", code: "CY-160-0426" },
      diaperType: "both",
      growthTab: "weight",
      growthDraft: { date: "2026-08-21", weight: "5.62", length: "58.4", posture: "卧位身长" },
      growthMeasurements: [
        { date: "2026-08-18", weight: "5.60", length: "58.2" },
        { date: "2026-07-12", weight: "4.72", length: "54.1" },
        { date: "2026-06-09", weight: "3.28", length: "49.5" }
      ],
      albumPhoto: false,
      albumDraftPhoto: false,
      historyFilter: "全部",
      latestSaved: null,
      events: [
        { id: "event_example_feed", type: "bottle", feedType: "formula", amount: 90, occurredAt: new Date("2026-08-21T14:20:00+08:00").getTime(), formulaCanId: sampleCanSnapshot.id, bottleId: sampleBottleSnapshot.id, formulaCanSnapshot: sampleCanSnapshot, bottleSnapshot: sampleBottleSnapshot, tone: "peach", title: "瓶喂 · 配方奶 90 ml", subtitle: "星禾初护（示例） · 小满的日用奶瓶", time: "14:20", ago: "1小时前" },
        { type: "diaper", tone: "gold", title: "尿布 · 小便 + 大便", subtitle: "由我记录", time: "13:45", ago: "2小时前" },
        { type: "sleep", tone: "blue", title: "睡眠 · 1小时18分", subtitle: "12:10 – 13:28", time: "12:10", ago: "3小时前" },
        { type: "nursing", tone: "", title: "亲喂 · 21分钟", subtitle: "成人侧别明细仅本人可见", time: "10:32", ago: "5小时前" }
      ]
    };
  }

  let state = initialState();

  function clone(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function saveState() {
    if (board) return;
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); } catch (_) { /* Prototype still works without storage. */ }
  }

  function loadState() {
    if (board) return;
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved) {
        const base = initialState();
        const parsed = JSON.parse(saved);
        state = {
          ...base,
          ...parsed,
          nursing: { ...base.nursing, ...(parsed.nursing || {}) },
          pump: { ...base.pump, ...(parsed.pump || {}) },
          bottleFeed: { ...base.bottleFeed, ...(parsed.bottleFeed || {}) },
          growthDraft: { ...base.growthDraft, ...(parsed.growthDraft || {}) }
        };
      }
    } catch (_) { state = initialState(); }
  }

  function formatDuration(totalSeconds, short = false) {
    const seconds = Math.max(0, Math.floor(totalSeconds || 0));
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = seconds % 60;
    if (short) return hours ? `${hours}小时${minutes}分` : `${minutes}分${String(secs).padStart(2, "0")}秒`;
    return `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}:${String(secs).padStart(2, "0")}`;
  }

  function formatClock(timestamp) {
    if (!timestamp) return "--:--";
    return new Date(timestamp).toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit", hour12: false });
  }

  function makeId(prefix) {
    const uuid = globalThis.crypto?.randomUUID?.() || `${Date.now()}_${Math.random().toString(36).slice(2, 9)}`;
    return `${prefix}_${uuid}`;
  }

  function parseDateOnly(value) {
    const [year, month, day] = String(value || "").split("-").map(Number);
    return new Date(Date.UTC(year || 1970, Math.max(0, (month || 1) - 1), day || 1));
  }

  function measurementAge(birthDate, measurementDate) {
    const birth = parseDateOnly(birthDate);
    const measured = parseDateOnly(measurementDate);
    if (measured <= birth) return "出生";
    let months = (measured.getUTCFullYear() - birth.getUTCFullYear()) * 12 + measured.getUTCMonth() - birth.getUTCMonth();
    if (measured.getUTCDate() < birth.getUTCDate()) months -= 1;
    const anchor = new Date(Date.UTC(birth.getUTCFullYear(), birth.getUTCMonth() + months, birth.getUTCDate()));
    const days = Math.max(0, Math.round((measured - anchor) / 86400000));
    return `${months > 0 ? `${months}个月` : ""}${days > 0 ? `${days}天` : ""}` || "出生";
  }

  function measurementDateParts(value) {
    const date = parseDateOnly(value);
    return { day: String(date.getUTCDate()).padStart(2, "0"), month: `${date.getUTCMonth() + 1}月` };
  }

  function sortedMeasurements(s) {
    return [...s.growthMeasurements].sort((a, b) => String(b.date).localeCompare(String(a.date)));
  }

  function nursingElapsed(s, side) {
    const n = s.nursing;
    const base = side === "left" ? n.leftBase : n.rightBase;
    if (!n.active || n.paused || n.currentSide !== side || !n.tickAt) return base;
    return base + (Date.now() - n.tickAt) / 1000;
  }

  function pumpElapsed(s, side) {
    const p = s.pump;
    const base = side === "left" ? p.leftBase : p.rightBase;
    const tick = side === "left" ? p.leftTick : p.rightTick;
    const ended = side === "left" ? p.leftEnded : p.rightEnded;
    if (!p.active || ended || !tick) return base;
    return base + (Date.now() - tick) / 1000;
  }

  function selectedPumpSides(p) {
    return p.mode === "double" ? ["left", "right"] : [p.singleSide || "left"];
  }

  function pumpFinished(p) {
    return selectedPumpSides(p).every((side) => side === "left" ? p.leftEnded : p.rightEnded);
  }

  function pumpUnionDuration(s) {
    const now = Date.now();
    const intervals = selectedPumpSides(s.pump).map((side) => {
      const start = s.pump[`${side}StartedAt`];
      const end = s.pump[`${side}EndedAt`] || (s.pump.active ? now : s.pump.endedAt);
      return start && end >= start ? [start, end] : null;
    }).filter(Boolean).sort((a, b) => a[0] - b[0]);
    if (!intervals.length) return 0;
    let total = 0;
    let [start, end] = intervals[0];
    for (const [nextStart, nextEnd] of intervals.slice(1)) {
      if (nextStart <= end) end = Math.max(end, nextEnd);
      else { total += end - start; start = nextStart; end = nextEnd; }
    }
    return (total + end - start) / 1000;
  }

  function statusBar(dark = false) {
    return `<div class="status-bar${dark ? " dark" : ""}"><span>9:41</span><span class="status-icons"><span class="signal-bars"><i></i><i></i><i></i><i></i></span><span>5G</span><span class="battery"></span></span></div>`;
  }

  function progressDots(active) {
    return `<div class="progress-dots" aria-label="第 ${active} 步，共 4 步">${[1, 2, 3, 4].map((n) => `<i class="${n === active ? "active" : ""}"></i>`).join("")}</div>`;
  }

  function backButton(fallback = "home", dark = false) {
    return `<button class="icon-button ${dark ? "" : "clear"}" data-back="${fallback}" aria-label="返回">${icon("back")}</button>`;
  }

  function pageHeader(title, fallback = "home", right = "") {
    return `<header class="page-header">${backButton(fallback)}<h1>${title}</h1>${right || "<span></span>"}</header>`;
  }

  function bottomNav(active = "home") {
    const items = [
      ["home", "今日", "home"],
      ["growth", "成长", "chart"],
      ["quick-add", "记录", "plus"],
      ["album", "相册", "album"],
      ["me", "我的", "user"]
    ];
    return `<nav class="bottom-nav" aria-label="主导航">${items.map(([screen, label, glyph], index) => `<button class="nav-item ${index === 2 ? "add" : ""} ${active === screen ? "active" : ""}" data-route="${screen}"><span>${icon(glyph)}</span><span>${label}</span></button>`).join("")}</nav>`;
  }

  function eventRow(event) {
    return `<article class="event-row"><span class="event-icon ${event.tone || ""}">${icon(event.type)}</span><div class="event-copy"><strong>${event.title}</strong><span>${event.subtitle}</span></div><div class="event-time"><b>${event.time}</b>${event.ago || ""}</div></article>`;
  }

  function moduleCard(s, key, title, copy, glyph, tone = "") {
    const selected = Boolean(s.modules[key]);
    return `<label class="module-card ${selected ? "selected" : ""}" data-module="${key}"><input type="checkbox" ${selected ? "checked" : ""}/><span class="fake-check">${icon("check")}</span><span class="module-icon ${tone}">${icon(glyph)}</span><strong>${title}</strong><p>${copy}</p></label>`;
  }

  function objectCard(kind, exists, s) {
    if (!exists) {
      const isCan = kind === "can";
      return `<button class="object-card missing" data-route="${isCan ? "formula-empty" : "bottle-create"}"><span class="object-thumb ${isCan ? "" : "bottle"}">${icon(isCan ? "can" : "bottle")}</span><span><strong>${isCan ? "还没有奶粉罐" : "还没有奶瓶档案"}</strong><p>${isCan ? "首次使用时拍摄包装与批次信息" : "建立后每次喂养可以快速复用"}</p></span>${icon("chevron")}</button>`;
    }
    if (kind === "can") {
      return `<button class="object-card" data-route="formula-detail"><span class="object-thumb">${icon("can")}</span><span><strong>${s.formulaCan.brand} · ${s.formulaCan.product}</strong><p>批次 ${s.formulaCan.lot} · 当前使用</p><span class="status-tag">资料已核对</span></span>${icon("chevron")}</button>`;
    }
    return `<button class="object-card" data-route="supplies"><span class="object-thumb bottle">${icon("bottle")}</span><span><strong>${s.bottle.nickname}</strong><p>${s.bottle.brand} · ${s.bottle.model}</p><span class="status-tag">最近使用</span></span>${icon("chevron")}</button>`;
  }

  function chartSvg(tab, measurements, babyBirth) {
    const ordered = [...measurements].sort((a, b) => String(a.date).localeCompare(String(b.date)));
    const numbers = ordered.map((item) => Number(item[tab === "weight" ? "weight" : "length"])).filter(Number.isFinite);
    const min = Math.min(...numbers);
    const max = Math.max(...numbers);
    const spread = Math.max(0.1, max - min);
    const points = ordered.map((item, index) => {
      const value = Number(item[tab === "weight" ? "weight" : "length"]);
      const x = ordered.length === 1 ? 150 : 16 + index * (262 / (ordered.length - 1));
      const y = 124 - ((value - min) / spread) * 96;
      return { x, y, age: measurementAge(babyBirth, item.date) };
    });
    const path = points.map((point, index) => `${index ? "L" : "M"}${point.x.toFixed(1)} ${point.y.toFixed(1)}`).join(" ");
    const compactAge = (age) => age === "出生" ? age : `${Number.parseInt(age, 10) || 0}月`;
    return `<svg class="chart" viewBox="0 0 300 158" role="img" aria-label="${tab === "weight" ? "体重" : "身长"}个人趋势图"><path class="band" d="M0 126 C60 103 108 71 154 55 S238 24 300 15 L300 53 C230 61 181 74 142 87 S61 124 0 145Z"/><path class="gridline" d="M0 30h300M0 76h300M0 122h300"/><path class="trend" d="${path}"/>${points.map((point, index) => `<circle class="point" cx="${point.x.toFixed(1)}" cy="${point.y.toFixed(1)}" r="${index === points.length - 1 ? 5 : 4}"/><text x="${Math.max(2, point.x - 8).toFixed(1)}" y="154">${compactAge(point.age)}</text>`).join("")}</svg>`;
  }

  function viewWelcome() {
    return `<section class="screen tinted">${statusBar()}<div class="onboarding"><div class="onboarding-visual" aria-hidden="true"><span class="moon"></span><span class="leaf one"></span><span class="leaf two"></span><span class="baby-orbit"></span><span class="baby-illustration"></span></div><div class="onboarding-copy"><span class="eyebrow">Mom-Baby</span><h1>每一次照护，<br/>都值得被轻轻记住</h1><p>几秒记录喂养、尿布和成长。数据默认保存在本机，由你决定是否开启私密云空间。</p></div><div class="onboarding-actions"><button class="btn primary" data-route="consent">开始使用 ${icon("chevron")}</button><div class="privacy-inline">${icon("lock")} 默认私密 · 不含广告与公开动态</div></div></div></section>`;
  }

  function viewConsent(s) {
    const ready = s.consentGuardian && s.consentChild;
    return `<section class="screen tinted">${statusBar()}<div class="screen-content no-nav">${pageHeader("使用前确认", "welcome")}${progressDots(1)}<div class="notice-card"><span class="notice-icon">${icon("shield")}</span><div><strong>先说明，再记录</strong><p>宝宝档案与照护数据属于敏感个人信息。首版无需注册也能在本机使用。</p></div></div><div class="consent-list"><label class="check-row ${s.consentGuardian ? "checked" : ""}" data-consent="guardian"><input type="checkbox" ${s.consentGuardian ? "checked" : ""}/><span class="fake-check">${icon("check")}</span><span><strong>我是宝宝的父母或其他法定监护人</strong><p>非监护人需要由监护人在家庭协作功能中邀请，不能自行建立宝宝档案。</p></span></label><label class="check-row ${s.consentChild ? "checked" : ""}" data-consent="child"><input type="checkbox" ${s.consentChild ? "checked" : ""}/><span class="fake-check">${icon("check")}</span><span><strong>单独同意处理宝宝的必要信息</strong><p>用于建立档案及本机记录。开启云空间时，我们会再次按类别征得同意。</p></span></label></div><button class="text-link" style="margin:16px 2px" data-action="show-policy">查看《儿童个人信息处理说明》</button><div class="save-dock"><button class="btn primary" data-route="baby-profile" ${ready ? "" : "disabled"}>同意并继续</button></div></div></section>`;
  }

  function viewBabyProfile(s) {
    return `<section class="screen">${statusBar()}<div class="screen-content no-nav">${pageHeader("宝宝建档", "consent")}${progressDots(2)}<div class="avatar-editor"><div class="avatar-large">${s.babyName.slice(0, 1) || "宝"}</div><button type="button">添加头像</button></div><div class="form-stack"><div class="field-group"><label for="baby-name">宝宝昵称</label><input id="baby-name" class="field" data-bind="babyName" value="${s.babyName}" placeholder="怎么称呼宝宝？"/></div><div class="field-group"><label for="baby-birth">出生日期</label><input id="baby-birth" class="field" type="date" data-bind="babyBirth" value="${s.babyBirth}"/></div><div class="field-group"><span class="field-label">生长参考分组 <span>用于匹配参考带</span></span><div class="segmented"><button class="${s.growthGroup === "女童" ? "active" : ""}" data-growth-group="女童">女童</button><button class="${s.growthGroup === "男童" ? "active" : ""}" data-growth-group="男童">男童</button></div></div><div class="helper-copy">${icon("info")} 生长参考只用于显示国家标准参考带，不代替医生判断，也不会给宝宝贴“正常/异常”标签。</div></div><div class="save-dock"><button class="btn primary" data-route="module-select">下一步：选择记录模块</button></div></div></section>`;
  }

  function viewModuleSelect(s) {
    return `<section class="screen tinted">${statusBar()}<div class="screen-content no-nav">${pageHeader("想记录什么？", "baby-profile")}${progressDots(3)}<p class="center muted" style="font-size:11px;line-height:1.5;margin:-8px 10px 2px">先选择现在用得到的，之后随时可以调整。</p><div class="module-grid">${moduleCard(s, "feeding", "喂养与吸奶", "亲喂、吸奶、奶瓶", "nursing")}${moduleCard(s, "diaper", "尿布", "小便、大便、混合", "diaper", "gold")}${moduleCard(s, "sleep", "睡眠", "计时与手工补录", "sleep", "blue")}${moduleCard(s, "growth", "生长", "身长与体重趋势", "chart")}${moduleCard(s, "album", "成长时光", "私密照片与月龄", "album", "peach")}</div><div class="save-dock"><button class="btn primary" data-action="finish-onboarding">进入${s.babyName}的今日</button></div></div></section>`;
  }

  function viewHome(s) {
    const nursingRoute = s.nursing.active ? "nursing-running" : "nursing-start";
    const pumpRoute = s.pump.active ? "pump-running" : "pump-start";
    const runningNursing = s.nursing.active ? `<button class="active-session-card" style="width:100%;text-align:left" data-route="nursing-running"><div class="session-top"><i class="pulse-dot"></i><strong>正在亲喂 · ${s.nursing.currentSide === "left" ? "左侧" : "右侧"}</strong><span class="session-time" data-timer="nursing-total">${formatDuration(nursingElapsed(s, "left") + nursingElapsed(s, "right"))}</span>${icon("chevron")}</div></button>` : "";
    const runningPump = s.pump.active ? `<button class="active-session-card" style="width:100%;text-align:left" data-route="pump-running"><div class="session-top"><i class="pulse-dot"></i><strong>正在${s.pump.mode === "double" ? "双边" : `${s.pump.singleSide === "right" ? "右侧" : "左侧"}`}吸奶</strong><span class="session-time" data-timer="pump-union">${formatDuration(pumpUnionDuration(s))}</span>${icon("chevron")}</div></button>` : "";
    return `<section class="screen">${statusBar()}<div class="screen-content"><header class="home-head"><div class="baby-avatar">满</div><div class="home-title"><p>2026年8月21日 · 星期五</p><h1>${s.babyName} · 2个月12天</h1></div><div class="home-actions"><button class="icon-button clear" data-route="history" aria-label="历史记录">${icon("history")}</button><button class="icon-button clear" data-action="cloud-info" aria-label="私密云空间">${icon("cloud")}</button></div></header><div class="date-strip">${[["一",17],["二",18],["三",19],["四",20],["五",21],["六",22],["日",23]].map(([w,d])=>`<div class="date-day ${d===21?"active":""}"><span>${w}</span><b>${d}</b></div>`).join("")}</div><section class="summary-hero"><span>距离上次喂养</span><h2>1小时 20分 <small>前</small></h2><div class="summary-meta"><div><b>48 分钟</b><span>今日亲喂</span></div><div><b>180 ml</b><span>今日奶瓶</span></div><div><b>5 次</b><span>今日尿布</span></div></div></section><div class="section-title"><h2>快速记录</h2><button data-route="quick-add">全部</button></div><div class="quick-grid"><button class="quick-tile" data-route="${nursingRoute}"><span class="quick-icon">${icon("nursing")}</span>${s.nursing.active ? "继续亲喂" : "亲喂"}</button><button class="quick-tile" data-route="bottle-feed"><span class="quick-icon peach">${icon("bottle")}</span>奶瓶</button><button class="quick-tile" data-route="diaper-add"><span class="quick-icon gold">${icon("diaper")}</span>尿布</button><button class="quick-tile" data-route="${pumpRoute}"><span class="quick-icon blue">${icon("pump")}</span>${s.pump.active ? "继续吸奶" : "吸奶"}</button></div>${runningNursing}${runningPump}<div class="section-title"><h2>今天</h2><button data-route="history">查看全部</button></div><div class="event-list">${s.events.slice(0,4).map(eventRow).join("")}</div></div>${bottomNav("home")}</section>`;
  }

  function viewQuickAdd(s) {
    const choices = [[s.nursing.active ? "nursing-running" : "nursing-start",s.nursing.active ? "继续亲喂" : "亲喂","nursing",""],[s.pump.active ? "pump-running" : "pump-start",s.pump.active ? "继续吸奶" : "吸奶","pump","blue"],["bottle-feed","奶瓶","bottle","peach"],["diaper-add","尿布","diaper","gold"],["sleep-add","睡眠","sleep","blue"],["growth-add","成长","chart",""]];
    return `<section class="screen sheet-screen"><button class="sheet-backdrop" data-route="home" aria-label="关闭"></button><div class="bottom-sheet"><div class="sheet-grabber"></div><div class="sheet-title"><h2>记录一件小事</h2><p>高频动作放在前面，时间默认就是现在。</p></div><div class="add-grid">${choices.map(([route,label,glyph,tone])=>`<button class="quick-tile" data-route="${route}"><span class="quick-icon ${tone}">${icon(glyph)}</span>${label}</button>`).join("")}</div><button class="btn ghost" style="margin-top:14px" data-route="album-add">${icon("photoAdd")} 添加成长照片</button></div></section>`;
  }

  function viewNursingStart(s) {
    if (s.nursing.active) return `<section class="screen tinted">${statusBar()}<div class="screen-content no-nav">${pageHeader("亲喂计时", "home")}<div class="notice-card"><span class="notice-icon">${icon("nursing")}</span><div><strong>已有一条亲喂正在计时</strong><p>${s.nursing.currentSide === "left" ? "左侧" : "右侧"} · ${formatDuration(nursingElapsed(s, "left") + nursingElapsed(s, "right"))}</p></div></div><button class="btn primary" style="margin-top:18px" data-route="nursing-running">继续当前亲喂</button></div></section>`;
    return `<section class="screen tinted">${statusBar()}<div class="screen-content no-nav">${pageHeader("开始亲喂", "home")}<div class="side-choice"><button class="side-button" data-action="nursing-start" data-side="left"><span class="side-arc">L</span><strong>开始左侧</strong><span>点击即开始计时</span></button><button class="side-button right" data-action="nursing-start" data-side="right"><span class="side-arc">R</span><strong>开始右侧</strong><span>点击即开始计时</span></button></div><div class="helper-copy">${icon("lock")} 宝宝记录只保存本次亲喂的开始、结束和总时长；左右侧明细属于哺乳者本人，默认不向家庭成员展示。</div><div class="section-title"><h2>或者补录</h2></div><button class="btn ghost" data-action="manual-record">${icon("edit")} 手工填写过去的记录</button></div></section>`;
  }

  function viewNursingRunning(s) {
    const n = s.nursing;
    const left = nursingElapsed(s, "left");
    const right = nursingElapsed(s, "right");
    const total = left + right;
    const activeSide = n.currentSide === "left" ? "左侧" : "右侧";
    return `<section class="screen dark-timer">${statusBar(true)}<header class="timer-header">${backButton("home", true)}<h1>亲喂计时</h1><button class="icon-button" data-action="timer-help" aria-label="说明">${icon("info")}</button></header><main class="timer-main"><div class="timer-status ${n.paused ? "paused" : ""}"><i></i>${n.paused ? "已暂停 · 时间不会累计" : `${activeSide}进行中`}</div><div class="timer-face"><span>本次总时长</span><strong data-timer="nursing-total">${formatDuration(total)}</strong><small>${formatClock(n.startedAt)} 开始</small></div><div class="segment-summary"><div class="segment-pill ${!n.paused && n.currentSide === "left" ? "active" : ""}"><span>左侧</span><b data-timer="nursing-left">${formatDuration(left)}</b></div><div class="segment-pill ${!n.paused && n.currentSide === "right" ? "active" : ""}"><span>右侧</span><b data-timer="nursing-right">${formatDuration(right)}</b></div></div><div class="timer-actions"><button class="timer-action" data-action="nursing-switch">${icon("switch")}<span>切到${n.currentSide === "left" ? "右" : "左"}侧</span></button><button class="timer-action main" data-action="nursing-pause">${icon(n.paused ? "play" : "pause")}<span>${n.paused ? "继续" : "暂停"}</span></button><button class="timer-action end" data-action="nursing-end">${icon("stop")}<span>结束</span></button></div></main></section>`;
  }

  function viewNursingDetail(s) {
    const left = Math.round(nursingElapsed(s, "left"));
    const right = Math.round(nursingElapsed(s, "right"));
    const total = left + right;
    const endedAt = s.nursing.endedAt || Date.now();
    const pausedSeconds = Math.max(0, Math.round((endedAt - s.nursing.startedAt) / 1000) - total);
    const segmentRows = s.nursing.segments.map((segment) => {
      const segmentEnd = segment.endedAt || endedAt;
      return `<div class="segment-line"><span>${formatClock(segment.startedAt)}–${formatClock(segmentEnd)}</span><b>${segment.side === "left" ? "左侧" : "右侧"}</b><span>${formatDuration((segmentEnd - segment.startedAt) / 1000, true)}</span></div>`;
    }).join("") || `<div class="helper-copy">${icon("info")} 暂无可展示的分侧时间段</div>`;
    return `<section class="screen">${statusBar()}<div class="screen-content no-nav">${pageHeader("亲喂详情", "home", `<button class="icon-button clear" data-action="edit-detail" aria-label="编辑">${icon("edit")}</button>`)}<section class="detail-hero"><div class="detail-type">${icon("nursing")} 已完成 · 亲喂</div><h2>${formatDuration(total, true)}</h2><p>${formatClock(s.nursing.startedAt)} – ${formatClock(endedAt)} · 系统计时生成</p></section><div class="stats-row"><div class="stat-card"><span>左侧</span><b>${formatDuration(left, true)}</b></div><div class="stat-card"><span>右侧</span><b>${formatDuration(right, true)}</b></div><div class="stat-card"><span>暂停</span><b>${formatDuration(pausedSeconds, true)}</b></div></div><div class="section-title"><h2>计时分段</h2><span>仅本人可见</span></div><div class="timeline-card">${segmentRows}</div><div class="section-title"><h2>给宝宝空间的记录</h2></div><div class="notice-card"><span class="notice-icon">${icon("shield")}</span><div><strong>已保存权威总时长快照</strong><p>家庭协作者只能看到开始、结束与总时长，不会看到左右侧分段。</p></div></div><div class="button-stack" style="margin-top:20px"><button class="btn primary" data-route="home">完成</button><button class="btn ghost" data-action="delete-demo">删除这条记录</button></div></div></section>`;
  }

  function viewPumpStart(s) {
    if (s.pump.active) return `<section class="screen tinted">${statusBar()}<div class="screen-content no-nav">${pageHeader("吸奶计时", "home")}<div class="notice-card"><span class="notice-icon">${icon("pump")}</span><div><strong>已有一条吸奶正在计时</strong><p>${s.pump.mode === "double" ? "双边" : s.pump.singleSide === "right" ? "右侧" : "左侧"} · ${formatDuration(pumpUnionDuration(s))}</p></div></div><button class="btn primary" style="margin-top:18px" data-route="pump-running">继续当前吸奶</button></div></section>`;
    return `<section class="screen tinted">${statusBar()}<div class="screen-content no-nav">${pageHeader("开始吸奶", "home")}<div class="section-title"><h2>选择方式</h2><span>本人私密记录</span></div><div class="mode-cards"><button class="select-card ${s.pump.mode === "double" ? "active" : ""}" data-pump-mode="double"><span class="module-icon blue">${icon("pump")}</span><span><strong>双边吸奶</strong><p>左右分别计时，可一侧先结束</p></span><i class="radio-dot"></i></button><button class="select-card ${s.pump.mode === "single" ? "active" : ""}" data-pump-mode="single"><span class="module-icon">${icon("pump")}</span><span><strong>单边吸奶</strong><p>开始前选择左侧或右侧</p></span><i class="radio-dot"></i></button></div>${s.pump.mode === "single" ? `<div class="segmented" style="margin-bottom:14px"><button class="${s.pump.singleSide === "left" ? "active" : ""}" data-pump-side="left">左侧</button><button class="${s.pump.singleSide === "right" ? "active" : ""}" data-pump-side="right">右侧</button></div>` : `<div class="notice-card"><span class="notice-icon">${icon("switch")}</span><div><strong>同时开始，分别结束</strong><p>有效总时长按左右工作时间的并集计算，不会把双边 20 分钟显示成 40 分钟。</p></div></div>`}<div class="save-dock"><button class="btn primary" data-action="pump-start">${s.pump.mode === "double" ? "双边同时开始" : `开始${s.pump.singleSide === "right" ? "右" : "左"}侧`}</button></div></div></section>`;
  }

  function viewPumpRunning(s) {
    const p = s.pump;
    const allEnded = pumpFinished(p);
    const sidePanel = (side) => {
      const ended = side === "left" ? p.leftEnded : p.rightEnded;
      const label = side === "left" ? "左侧" : "右侧";
      return `<div class="pump-side ${ended ? "ended" : ""}"><span class="side-label">${side.toUpperCase()} · ${label}</span><strong data-timer="pump-${side}">${formatDuration(pumpElapsed(s, side))}</strong><span class="state-copy">${ended ? "已结束" : "进行中"}</span><button data-action="pump-end-side" data-side="${side}" ${ended ? "disabled" : ""}>${ended ? icon("check") + " 已结束" : `结束${label}`}</button></div>`;
    };
    return `<section class="screen dark-timer">${statusBar(true)}<header class="timer-header">${backButton("home", true)}<h1>${p.mode === "double" ? "双边吸奶" : `${p.singleSide === "right" ? "右侧" : "左侧"}吸奶`}</h1><button class="icon-button" data-action="timer-help">${icon("info")}</button></header><main class="timer-main"><div class="timer-status"><i></i>${allEnded ? "计时已完成" : p.mode === "double" ? "正在记录 · 可分侧结束" : "正在记录"}</div><div class="pump-panels" style="${p.mode === "single" ? "grid-template-columns:1fr" : ""}">${selectedPumpSides(p).map(sidePanel).join("")}</div><div class="union-time"><span>本次有效总时长</span><b data-timer="pump-union">${formatDuration(pumpUnionDuration(s))}</b></div><div class="helper-copy" style="margin-top:12px;color:#bbc8c0;background:rgb(255 255 255 / 5%)">${icon("lock")} 吸奶时间与产量属于哺乳者本人数据，不改变宝宝“上次喂养”。</div><div style="margin-top:auto;padding-top:18px"><button class="btn ${allEnded ? "primary" : "ghost"}" style="${allEnded ? "" : "color:#e4eae6;border-color:rgb(255 255 255 / 13%)"}" data-action="pump-finish">${allEnded ? "填写吸奶量" : "结束剩余侧并填写用量"}</button></div></main></section>`;
  }

  function viewPumpVolume(s) {
    const p = s.pump;
    const total = Number(p.leftVolume) + Number(p.rightVolume);
    const sideFields = selectedPumpSides(p).map((side) => `<div class="field-group"><label>${side === "left" ? "左侧" : "右侧"}</label><div class="input-with-unit"><input class="field" type="number" value="${p[`${side}Volume`]}" data-bind-pump="${side}Volume"/><span>ml</span></div></div>`).join("");
    return `<section class="screen">${statusBar()}<div class="screen-content no-nav">${pageHeader("记录吸奶量", "pump-running")}<div class="volume-hero"><div class="volume-ring"><strong>${total}</strong><span>毫升 · 本次总量</span></div></div>${p.mode === "double" ? `<div class="field-group"><span class="field-label">记录方式 <span>不会自动平分</span></span><div class="segmented"><button class="${p.volumeMode === "sides" ? "active" : ""}" data-volume-mode="sides">分别填写</button><button class="${p.volumeMode === "total" ? "active" : ""}" data-volume-mode="total">只填总量</button></div></div>` : ""}<div class="spacer-16"></div>${p.volumeMode === "sides" || p.mode === "single" ? `<div class="${p.mode === "double" ? "two-fields" : "form-stack"}">${sideFields}</div>` : `<div class="field-group"><label>本次总量</label><div class="input-with-unit"><input class="field" type="number" value="${total}" data-bind-pump="totalVolume"/><span>ml</span></div></div>`}<div class="helper-copy" style="margin-top:14px">${icon("info")} 如果只知道总量，可以只填写总量；系统不会编造左右侧分配。</div><div class="save-dock"><button class="btn primary" data-action="pump-save">保存吸奶记录</button></div></div></section>`;
  }

  function viewPumpDetail(s) {
    const p = s.pump;
    const left = Math.round(p.leftBase);
    const right = Math.round(p.rightBase);
    const totalMl = Number(p.leftVolume) + Number(p.rightVolume);
    const sideRows = selectedPumpSides(p).map((side) => {
      const startedAt = p[`${side}StartedAt`];
      const endedAt = p[`${side}EndedAt`] || p.endedAt;
      return `<div class="segment-line"><span>${formatClock(startedAt)}–${formatClock(endedAt)}</span><b>${side === "left" ? "左侧" : "右侧"}</b><span>${formatDuration(side === "left" ? left : right,true)}</span></div>`;
    }).join("");
    const sideStats = selectedPumpSides(p).map((side) => `<div class="stat-card"><span>${side === "left" ? "左侧" : "右侧"}</span><b>${p[`${side}Volume`]} ml</b></div>`).join("");
    return `<section class="screen">${statusBar()}<div class="screen-content no-nav">${pageHeader("吸奶详情", "home", `<button class="icon-button clear">${icon("edit")}</button>`)}<div class="success-mark">${icon("check")}</div><div class="center"><span class="eyebrow">已保存到本人记录</span><h1 style="font-family:Georgia,'Songti SC',serif;font-size:28px;font-weight:500;margin:8px 0 4px">${totalMl} ml</h1><p class="muted" style="font-size:11px;margin:0">${p.mode === "double" ? "双边" : p.singleSide === "right" ? "右侧" : "左侧"}吸奶 · ${formatClock(p.startedAt)}–${formatClock(p.endedAt)} · 有效 ${formatDuration(pumpUnionDuration(s), true)}</p></div><div class="stats-row" style="margin-top:24px">${sideStats}<div class="stat-card"><span>合计</span><b>${totalMl} ml</b></div></div><div class="section-title"><h2>分侧时间</h2><span>仅本人可见</span></div><div class="timeline-card">${sideRows}</div><div class="helper-copy" style="margin-top:14px">${icon("shield")} 这条吸奶记录没有加入宝宝喂养流水。将来使用这批母乳瓶喂时，再记录宝宝实际喝下量。</div><button class="btn primary" style="margin-top:22px" data-route="home">完成</button></div></section>`;
  }

  function viewBottleFeed(s) {
    const f = s.bottleFeed;
    const isFormula = f.type === "formula";
    const ready = isFormula ? Boolean(s.formulaCan && s.bottle) : Boolean(s.bottle);
    const incompleteCopy = isFormula
      ? "紧急喂养时可以先保存，稍后补充奶粉罐或奶瓶；未关联完整用品时会标记“追溯资料不完整”。"
      : "可以先保存母乳瓶喂，稍后补充奶瓶；母乳瓶喂不要求关联奶粉罐。";
    return `<section class="screen tinted">${statusBar()}<div class="screen-content no-nav">${pageHeader("记录奶瓶喂养", "home")}<div class="segmented feed-type-tabs"><button class="${isFormula ? "active" : ""}" data-feed-type="formula">配方奶</button><button class="${!isFormula ? "active" : ""}" data-feed-type="breastmilk">母乳</button></div><div class="field-label">宝宝实际喝下量 <span>必填</span></div><div class="amount-control"><button data-amount="-10" aria-label="减少 10 毫升">−</button><div class="amount-value"><strong>${f.amount}</strong><span>ml</span></div><button data-amount="10" aria-label="增加 10 毫升">＋</button></div>${isFormula ? `<div class="section-title"><h2>使用的奶粉罐</h2><button data-route="formula-empty">${s.formulaCan ? "更换" : "添加"}</button></div>${objectCard("can", s.formulaCan, s)}` : ""}<div class="section-title"><h2>使用的奶瓶</h2><button data-route="bottle-create">${s.bottle ? "更换" : "添加"}</button></div>${objectCard("bottle", s.bottle, s)}<div class="field-group" style="margin-top:16px"><label>备注 <span>选填</span></label><textarea class="field" data-bind-feed="note" placeholder="例如：剩余 10 ml">${f.note}</textarea></div>${!ready ? `<div class="disclaimer">${icon("info")} ${incompleteCopy}</div>` : ""}<div class="save-dock"><button class="btn primary" data-action="save-bottle-feed">${ready ? `保存 ${f.amount} ml ${isFormula ? "配方奶" : "母乳"}` : `保存，稍后补充${isFormula ? "追溯资料" : "奶瓶"}`}</button></div></div></section>`;
  }

  function viewFormulaEmpty() {
    return `<section class="screen">${statusBar()}<div class="screen-content no-nav">${pageHeader("奶粉罐", "bottle-feed")}<div class="empty-state"><div class="empty-visual">${icon("can")}<span class="plus-on-visual">＋</span></div><h2>还没有正在使用的奶粉罐</h2><p>每罐只需建档一次。之后的配方奶记录会自动预选最近使用的一罐，便于按批次反查喂养时间。</p></div><div class="notice-card"><span class="notice-icon">${icon("camera")}</span><div><strong>准备拍摄 3 张照片</strong><p>包装正面、批次/日期、溯源码。照片只作为核对证据，不会进入宝宝成长相册。</p></div></div><div class="disclaimer">${icon("info")} 保存资料不等于已核验产品安全。MVP 不会仅凭照片自动作出召回或安全判断。</div><div class="save-dock"><button class="btn primary" data-route="formula-capture-front">开始建立奶粉罐</button></div></div></section>`;
  }

  const captureMeta = {
    front: { title: "包装正面", index: 1, glyph: "can", copy: "让品牌、完整产品名和段位清晰入镜", next: "formula-capture-batch" },
    batch: { title: "批次与日期", index: 2, glyph: "tag", copy: "对准批号、生产日期和保质期标注区域", next: "formula-capture-code" },
    code: { title: "溯源码", index: 3, glyph: "qr", copy: "完整拍下二维码或企业追溯码，避免反光", next: "formula-verify" }
  };

  function viewCapture(s, step) {
    const meta = captureMeta[step];
    const done = s.capture[step];
    return `<section class="screen tinted">${statusBar()}<div class="screen-content no-nav">${pageHeader(`${meta.index}/3 · ${meta.title}`, step === "front" ? "formula-empty" : step === "batch" ? "formula-capture-front" : "formula-capture-batch")}<div class="capture-progress">${[1,2,3].map((n)=>`<i class="${n<=meta.index?"done":""}"></i>`).join("")}</div><div class="camera-frame ${done ? "captured" : ""}"><div class="camera-guide"></div><div class="camera-copy">${icon(done ? "check" : meta.glyph)}<strong>${done ? `${meta.title}已拍摄` : meta.title}</strong><span>${done ? "原型使用示意图；实际 App 将保存清晰原图与缩略图。" : meta.copy}</span></div></div><div class="capture-actions"><button class="icon-button" data-action="capture-tip" aria-label="拍摄提示">${icon("info")}</button><button class="shutter" data-action="capture-photo" data-capture="${step}" aria-label="模拟拍摄"></button><button class="icon-button" data-action="capture-photo" data-capture="${step}" aria-label="从相册选择">${icon("image")}</button></div><div class="save-dock"><button class="btn primary" data-route="${meta.next}" ${done ? "" : "disabled"}>${step === "code" ? "核对识别结果" : "下一张"}</button></div></div></section>`;
  }

  function viewFormulaVerify(s) {
    const d = s.formulaDraft;
    return `<section class="screen">${statusBar()}<div class="screen-content no-nav">${pageHeader("核对奶粉罐资料", "formula-capture-code")}<div class="evidence-strip"><div class="evidence-thumb">${icon("can")}包装正面</div><div class="evidence-thumb">${icon("tag")}批次日期</div><div class="evidence-thumb">${icon("qr")}溯源码</div></div><div class="form-stack"><div class="field-group"><label>品牌</label><input class="field" data-bind-formula="brand" value="${d.brand}"/></div><div class="field-group"><label>完整产品名</label><input class="field" data-bind-formula="product" value="${d.product}"/></div><div class="two-fields"><div class="field-group"><label>阶段</label><input class="field" data-bind-formula="stage" value="${d.stage}"/></div><div class="field-group"><label>批次号</label><input class="field" data-bind-formula="lot" value="${d.lot}"/></div></div><div class="two-fields"><div class="field-group"><label>生产日期</label><input class="field" type="date" data-bind-formula="produced" value="${d.produced}"/></div><div class="field-group"><label>保质期至</label><input class="field" type="date" data-bind-formula="expires" value="${d.expires}"/></div></div><div class="field-group"><label>溯源码原文</label><input class="field" data-bind-formula="trace" value="${d.trace}"/></div></div><div class="disclaimer">${icon("info")} OCR/扫码只是录入建议。请对照包装确认批次与日期；未知二维码网址不会自动打开。</div><div class="save-dock"><button class="btn primary" data-action="save-formula-can">我已对照包装核对</button></div></div></section>`;
  }

  function viewBottleCreate(s) {
    const d = s.bottleDraft;
    return `<section class="screen tinted">${statusBar()}<div class="screen-content no-nav">${pageHeader("建立奶瓶档案", "bottle-feed")}<div class="avatar-editor"><div class="avatar-large" style="color:#665c70;background:var(--lavender-100)">${icon("bottle")}</div><button type="button" data-action="bottle-photo">拍摄标识</button></div><div class="form-stack"><div class="field-group"><label>奶瓶昵称 <span>必填</span></label><input class="field" data-bind-bottle="nickname" value="${d.nickname}"/></div><div class="two-fields"><div class="field-group"><label>品牌</label><input class="field" data-bind-bottle="brand" value="${d.brand}"/></div><div class="field-group"><label>型号 / 容量</label><input class="field" data-bind-bottle="model" value="${d.model}"/></div></div><div class="field-group"><label>稳定标识或生产信息 <span>选填</span></label><input class="field" data-bind-bottle="code" value="${d.code}"/></div><div class="helper-copy">${icon("info")} 只有昵称也可以开始使用；补充品牌、型号和稳定标识后，未来更容易对照消费品召回公告。</div></div><div class="save-dock"><button class="btn primary" data-action="save-bottle">保存并用于本次喂养</button></div></div></section>`;
  }

  function viewDiaperAdd(s) {
    const choices = [["wet","小便","milk","blue"],["dirty","大便","diaper","gold"],["both","混合","diaper","peach"]];
    return `<section class="screen tinted">${statusBar()}<div class="screen-content no-nav">${pageHeader("记录尿布", "home")}<div class="center" style="padding:10px 0 17px"><span class="eyebrow">现在 · 15:40</span><h2 style="margin:8px 0 0;font-family:Georgia,'Songti SC',serif;font-size:25px;font-weight:500">刚刚换了什么？</h2></div><div class="mode-cards">${choices.map(([type,label,glyph,tone])=>`<button class="select-card ${s.diaperType===type?"active":""}" data-diaper="${type}"><span class="module-icon ${tone}">${icon(glyph)}</span><span><strong>${label}</strong><p>${type==="both"?"同时计入小便与大便分类":"一次换尿布记录"}</p></span><i class="radio-dot"></i></button>`).join("")}</div><div class="field-group"><label>备注 <span>选填</span></label><textarea class="field" placeholder="颜色、状态或其他想记住的事"></textarea></div><div class="helper-copy" style="margin-top:14px">${icon("info")} Mom-Baby 只记录你输入的事实，不根据尿布内容自动判断健康状况。</div><div class="save-dock"><button class="btn primary" data-action="save-diaper">保存尿布记录</button></div></div></section>`;
  }

  function viewSleepAdd() {
    return `<section class="screen dark-timer">${statusBar(true)}<header class="timer-header">${backButton("home", true)}<h1>睡眠计时</h1><span></span></header><main class="timer-main"><div class="timer-status"><i></i>准备开始</div><div class="timer-face"><span>宝宝睡着后</span><strong style="font-size:30px">点击开始</strong><small>时间由按钮自动生成</small></div><div class="helper-copy" style="color:#bbc8c0;background:rgb(255 255 255 / 5%)">${icon("info")} 跨午夜的睡眠会保留真实起止时间，并按宝宝家庭时区汇总。</div><div style="margin-top:auto"><button class="btn primary" data-action="save-sleep">开始睡眠计时</button></div></main></section>`;
  }

  function viewGrowth(s) {
    const measurements = sortedMeasurements(s);
    const latest = measurements[0];
    const latestParts = measurementDateParts(latest.date);
    const isWeight = s.growthTab === "weight";
    return `<section class="screen tinted">${statusBar()}<div class="screen-content"><header class="page-header has-copy"><div class="header-copy"><p>${s.babyName} · ${measurementAge(s.babyBirth, "2026-08-21")}</p><h1>成长趋势</h1></div><button class="icon-button sage" data-route="growth-add" aria-label="新增测量">${icon("plus")}</button></header><div class="segmented" style="margin-bottom:14px"><button class="${isWeight?"active":""}" data-growth-tab="weight">体重</button><button class="${!isWeight?"active":""}" data-growth-tab="length">身长</button></div><section class="chart-card"><div class="chart-top"><div><span>最近一次 · ${latestParts.month}${latestParts.day}日</span><strong>${isWeight?latest.weight:latest.length} <small style="font-size:11px;color:var(--muted)">${isWeight?"kg":"cm"}</small></strong></div><span class="trend-badge">个人趋势</span></div>${chartSvg(s.growthTab, measurements, s.babyBirth)}<div class="chart-caption">${icon("info")} 淡绿色仅表示 WS/T 423—2022 对应参考带，不作诊断或“正常/异常”判断。</div></section><div class="section-title"><h2>测量记录</h2><button data-route="growth-add">新增</button></div><div class="surface-card">${measurements.map((m)=>{const parts=measurementDateParts(m.date);return `<div class="measure-row"><div class="measure-date"><b>${parts.day}</b>${parts.month}</div><div class="measure-copy"><strong>${measurementAge(s.babyBirth,m.date)}</strong><span>${m.date}</span></div><span class="measure-value">${isWeight?`${m.weight} kg`:`${m.length} cm`}</span></div>`;}).join("")}</div></div>${bottomNav("growth")}</section>`;
  }

  function viewGrowthAdd(s) {
    const d = s.growthDraft;
    return `<section class="screen">${statusBar()}<div class="screen-content no-nav">${pageHeader("新增测量", "growth")}<div class="form-stack"><div class="field-group"><label>测量日期</label><input class="field" type="date" data-bind-growth="date" value="${d.date}"/></div><div class="field-group"><label>体重</label><div class="input-with-unit"><input class="field" type="number" step="0.01" data-bind-growth="weight" value="${d.weight}"/><span>kg</span></div></div><div class="field-group"><label>身长 / 身高</label><div class="input-with-unit"><input class="field" type="number" step="0.1" data-bind-growth="length" value="${d.length}"/><span>cm</span></div></div><div class="field-group"><span class="field-label">测量方式</span><div class="segmented"><button class="${d.posture==="卧位身长"?"active":""}" data-posture="卧位身长">卧位身长</button><button class="${d.posture==="站立身高"?"active":""}" data-posture="站立身高">站立身高</button></div></div><div class="field-group"><label>备注 <span>选填</span></label><textarea class="field" placeholder="例如：社区体检测量"></textarea></div></div><div class="disclaimer">${icon("info")} 不同测量方式不能静默混用。个人趋势用于整理记录，如对生长有疑问请咨询专业医务人员。</div><div class="save-dock"><button class="btn primary" data-action="save-growth">保存测量</button></div></div></section>`;
  }

  function viewAlbum(s) {
    const content = s.albumPhoto ? `<div class="section-title"><h2>8月21日</h2><span>2个月12天</span></div><div class="photo-grid"><article class="photo-tile tall"><div class="photo-label"><strong>今天第一次抬头很久</strong><span>15:26 · 本机私密保存</span></div></article><article class="photo-tile" style="background:linear-gradient(145deg,#e9dece,#d7e2d8)"><div class="photo-label"><strong>午睡后的笑脸</strong><span>12:08</span></div></article><article class="photo-tile" style="background:linear-gradient(145deg,#dfe8e0,#e8d4cd)"></article></div>` : `<div class="album-hero-empty"><div class="empty-state"><div class="photo-empty-visual"><span class="photo-card-shape one"></span><span class="photo-card-shape two"></span><span class="photo-plus">＋</span></div><h2>从第一张成长照片开始</h2><p>照片按拍摄日期和宝宝月龄整理。默认仅保存在本机，开启私密云空间后才会上传。</p><button class="btn primary small" style="margin-top:18px" data-route="album-add">添加照片</button></div></div>`;
    return `<section class="screen">${statusBar()}<div class="screen-content"><header class="page-header has-copy"><div class="header-copy"><p>仅你可见 · 本机空间</p><h1>成长时光</h1></div><button class="icon-button sage" data-route="album-add" aria-label="添加照片">${icon("plus")}</button></header>${content}</div>${bottomNav("album")}</section>`;
  }

  function viewAlbumAdd(s) {
    return `<section class="screen tinted">${statusBar()}<div class="screen-content no-nav">${pageHeader("添加成长照片", "album")}<button class="upload-drop ${s.albumDraftPhoto?"has-photo":""}" data-action="album-pick">${icon(s.albumDraftPhoto?"check":"photoAdd")}<strong>${s.albumDraftPhoto?"已选择 1 张照片":"拍照或从系统照片选择"}</strong><span>${s.albumDraftPhoto?"拍摄于 2026年8月21日 15:26":"无需授予完整照片库权限"}</span></button><div class="form-stack" style="margin-top:18px"><div class="field-group"><label>照片说明 <span>选填</span></label><textarea class="field" placeholder="今天发生了什么？">${s.albumDraftPhoto?"今天第一次抬头很久":""}</textarea></div><div class="field-group"><label>归档日期</label><input class="field" type="date" value="2026-08-21"/></div></div><div class="notice-card" style="margin-top:14px"><span class="notice-icon">${icon("lock")}</span><div><strong>不会公开发布</strong><p>奶粉与奶瓶证据图使用独立存储，不会出现在成长相册中。</p></div></div><div class="save-dock"><button class="btn primary" data-action="save-photo" ${s.albumDraftPhoto?"":"disabled"}>保存到成长时光</button></div></div></section>`;
  }

  function viewHistory(s) {
    const filters = ["全部","喂养","尿布","睡眠","成长"];
    return `<section class="screen tinted">${statusBar()}<div class="screen-content no-nav">${pageHeader("全部记录", "home", `<button class="icon-button clear">${icon("search")}</button>`)}<div class="filter-chips">${filters.map((f)=>`<button class="filter-chip ${s.historyFilter===f?"active":""}" data-history-filter="${f}">${f}</button>`).join("")}</div><section class="history-day"><h2>今天 · 8月21日</h2><div class="history-card">${s.events.map(eventRow).join("")}</div></section><section class="history-day"><h2>昨天 · 8月20日</h2><div class="history-card">${eventRow({type:"bottle",tone:"peach",title:"瓶喂 · 母乳 80 ml",subtitle:"小满的日用奶瓶",time:"21:48",ago:""})}${eventRow({type:"diaper",tone:"gold",title:"尿布 · 小便",subtitle:"由我记录",time:"20:15",ago:""})}${eventRow({type:"sleep",tone:"blue",title:"睡眠 · 2小时06分",subtitle:"17:42 – 19:48",time:"17:42",ago:""})}</div></section></div></section>`;
  }

  function viewMe(s) {
    const rows = [["supplies","box","用品档案","奶粉罐与奶瓶"],["baby-profile","heart","宝宝资料",`${s.babyName} · 2026年6月9日出生`],["cloud-info","cloud","私密云空间","未开启 · 当前仅本机保存"],["export-info","export","导出与数据控制","CSV、照片保存与删除"],["settings-info","settings","隐私与设置","同意管理、外观与无障碍"]];
    return `<section class="screen tinted">${statusBar()}<div class="screen-content"><header class="page-header has-copy"><div class="header-copy"><p>监护人 · 本地试用</p><h1>我的</h1></div><button class="icon-button clear">${icon("bell")}</button></header><div class="profile-hero"><div class="baby-avatar">满</div><div><h2>${s.babyName}的私密空间</h2><p>本机使用中 · 4 类记录 · 1 个照护者</p></div></div><div class="section-title"><h2>空间管理</h2></div><div class="menu-list">${rows.map(([action,glyph,title,copy])=>`<button class="menu-row" ${action.includes("-")&&!["supplies","baby-profile"].includes(action)?`data-action="${action}"`:`data-route="${action}"`}><span class="menu-icon">${icon(glyph)}</span><span class="menu-copy"><strong>${title}</strong><span>${copy}</span></span>${icon("chevron")}</button>`).join("")}</div><div class="section-title"><h2>关于</h2></div><div class="menu-list"><button class="menu-row" data-action="about"><span class="menu-icon">${icon("info")}</span><span class="menu-copy"><strong>关于 Mom-Baby</strong><span>MVP 原型 · v0.3</span></span>${icon("chevron")}</button></div></div>${bottomNav("me")}</section>`;
  }

  function viewSupplies(s) {
    return `<section class="screen tinted">${statusBar()}<div class="screen-content no-nav">${pageHeader("用品档案", "me", `<button class="icon-button sage" data-route="formula-empty">${icon("plus")}</button>`)}<div class="notice-card"><span class="notice-icon">${icon("box")}</span><div><strong>一次建档，记录时快速复用</strong><p>历史喂养保留当时版本，不会因为后来修改名称而静默变化。</p></div></div><div class="supply-header"><h2>正在使用的奶粉罐</h2><span class="supply-count">${s.formulaCan?1:0}</span></div>${s.formulaCan?`<button class="supply-card" style="width:100%;text-align:left" data-route="formula-detail"><span class="object-thumb">${icon("can")}</span><span><strong>${s.formulaCan.brand} · 1 段</strong><p>批次 ${s.formulaCan.lot}<br/>2026年8月18日开启</p><span class="status-tag">资料已核对</span></span>${icon("chevron")}</button>`:`<div class="supply-empty">尚未建立奶粉罐 · 配方奶记录时也可添加</div>`}<div class="supply-header"><h2>我的奶瓶</h2><span class="supply-count">${s.bottle?1:0}</span></div>${s.bottle?`<button class="supply-card" style="width:100%;text-align:left" data-route="bottle-create"><span class="object-thumb bottle">${icon("bottle")}</span><span><strong>${s.bottle.nickname}</strong><p>${s.bottle.brand} · ${s.bottle.model}<br/>最近使用：今天 14:20</p></span>${icon("chevron")}</button>`:`<button class="supply-empty" style="width:100%" data-route="bottle-create">尚未建立奶瓶 · 点击添加</button>`}<button class="btn ghost" style="margin-top:20px" data-route="bottle-create">${icon("plus")} 新建奶瓶</button></div></section>`;
  }

  function viewFormulaDetail(s) {
    const can = s.formulaCan || { id:"can_example_preview", brand:"星禾初护（示例）", product:"婴儿配方奶粉 1 段（示例）", lot:"CN260718A3", produced:"2026-07-18", expires:"2028-07-17", trace:"6930000123456 / X8F2" };
    const uses = s.events.filter((event) => event.feedType === "formula" && event.formulaCanId === can.id);
    const totalMl = uses.reduce((sum, event) => sum + Number(event.amount || 0), 0);
    const usageRows = uses.length ? uses.map((event) => eventRow({ type:"bottle", tone:"peach", title:`配方奶 ${event.amount} ml`, subtitle:event.bottleSnapshot?.nickname || "奶瓶未关联", time:formatClock(event.occurredAt), ago:"今天" })).join("") : `<div class="supply-empty">这罐奶粉尚未关联任何瓶喂记录</div>`;
    return `<section class="screen">${statusBar()}<div class="screen-content no-nav">${pageHeader("奶粉罐详情", "supplies", `<button class="icon-button clear">${icon("edit")}</button>`)}<section class="detail-hero"><div class="detail-type">${icon("can")} 当前使用 · 资料已核对</div><h2 style="font-size:22px">${can.brand}</h2><p>${can.product}</p></section><div class="evidence-strip"><div class="evidence-thumb">${icon("can")}包装正面</div><div class="evidence-thumb">${icon("tag")}批次日期</div><div class="evidence-thumb">${icon("qr")}溯源码</div></div><div class="surface-card"><div class="segment-line"><span>批次</span><b>${can.lot}</b><span>已确认</span></div><div class="segment-line"><span>生产</span><b>${can.produced}</b><span></span></div><div class="segment-line"><span>有效期</span><b>${can.expires}</b><span></span></div></div><div class="section-title"><h2>使用时间线</h2><span>共 ${uses.length} 次 · ${totalMl} ml</span></div><div class="history-card">${usageRows}</div><div class="disclaimer">${icon("info")} “暂无匹配信息”不代表产品安全。本 MVP 仅保存证据与使用时间线，尚未启用主动召回监测。</div></div></section>`;
  }

  function screenMarkup(screen, s = state) {
    switch (screen) {
      case "welcome": return viewWelcome(s);
      case "consent": return viewConsent(s);
      case "baby-profile": return viewBabyProfile(s);
      case "module-select": return viewModuleSelect(s);
      case "home": return viewHome(s);
      case "quick-add": return viewQuickAdd(s);
      case "nursing-start": return viewNursingStart(s);
      case "nursing-running": return viewNursingRunning(s);
      case "nursing-detail": return viewNursingDetail(s);
      case "pump-start": return viewPumpStart(s);
      case "pump-running": return viewPumpRunning(s);
      case "pump-volume": return viewPumpVolume(s);
      case "pump-detail": return viewPumpDetail(s);
      case "bottle-feed": return viewBottleFeed(s);
      case "formula-empty": return viewFormulaEmpty(s);
      case "formula-capture-front": return viewCapture(s, "front");
      case "formula-capture-batch": return viewCapture(s, "batch");
      case "formula-capture-code": return viewCapture(s, "code");
      case "formula-verify": return viewFormulaVerify(s);
      case "bottle-create": return viewBottleCreate(s);
      case "diaper-add": return viewDiaperAdd(s);
      case "sleep-add": return viewSleepAdd(s);
      case "growth": return viewGrowth(s);
      case "growth-add": return viewGrowthAdd(s);
      case "album": return viewAlbum(s);
      case "album-add": return viewAlbumAdd(s);
      case "history": return viewHistory(s);
      case "me": return viewMe(s);
      case "supplies": return viewSupplies(s);
      case "formula-detail": return viewFormulaDetail(s);
      default: return viewHome(s);
    }
  }

  function render() {
    if (!app) return;
    app.innerHTML = screenMarkup(state.screen, state);
    document.querySelectorAll("[data-jump]").forEach((button) => button.classList.toggle("active", button.dataset.jump === state.screen));
    saveState();
    requestAnimationFrame(updateLiveTimers);
  }

  function go(screen) {
    if (!screen) return;
    state.previous = state.screen;
    state.screen = screen;
    render();
  }

  let toastTimer;
  function toast(message) {
    if (!toastEl) return;
    clearTimeout(toastTimer);
    toastEl.textContent = message;
    toastEl.classList.add("show");
    toastTimer = setTimeout(() => toastEl.classList.remove("show"), 2200);
  }

  function freezeNursing(at = Date.now()) {
    const n = state.nursing;
    if (!n.active || n.paused || !n.tickAt) return;
    const elapsed = (at - n.tickAt) / 1000;
    if (n.currentSide === "left") n.leftBase += elapsed;
    else n.rightBase += elapsed;
    const openSegment = [...n.segments].reverse().find((segment) => !segment.endedAt);
    if (openSegment) openSegment.endedAt = at;
    n.tickAt = 0;
  }

  function freezePumpSide(side, at = Date.now()) {
    const p = state.pump;
    const tickKey = side === "left" ? "leftTick" : "rightTick";
    const baseKey = side === "left" ? "leftBase" : "rightBase";
    if (!p[tickKey]) return;
    p[baseKey] += (at - p[tickKey]) / 1000;
    p[tickKey] = 0;
    p[`${side}EndedAt`] = at;
  }

  function addEventOnce(key, event) {
    if (state.latestSaved === key) return;
    state.events.unshift(event);
    state.latestSaved = key;
  }

  function updateLiveTimers() {
    if (!app) return;
    app.querySelectorAll("[data-timer]").forEach((node) => {
      switch (node.dataset.timer) {
        case "nursing-left": node.textContent = formatDuration(nursingElapsed(state, "left")); break;
        case "nursing-right": node.textContent = formatDuration(nursingElapsed(state, "right")); break;
        case "nursing-total": node.textContent = formatDuration(nursingElapsed(state, "left") + nursingElapsed(state, "right")); break;
        case "pump-left": node.textContent = formatDuration(pumpElapsed(state, "left")); break;
        case "pump-right": node.textContent = formatDuration(pumpElapsed(state, "right")); break;
        case "pump-union": node.textContent = formatDuration(pumpUnionDuration(state)); break;
      }
    });
  }

  function handleClick(event) {
    const target = event.target.closest("button, [data-consent], [data-module]");
    if (!target || target.disabled) return;

    if (target.dataset.route) {
      go(target.dataset.route);
      return;
    }
    if (target.dataset.back) {
      go(target.dataset.back || state.previous || "home");
      return;
    }
    if (target.dataset.jump) {
      go(target.dataset.jump);
      return;
    }
    if (target.dataset.consent) {
      const key = target.dataset.consent === "guardian" ? "consentGuardian" : "consentChild";
      state[key] = !state[key];
      render();
      return;
    }
    if (target.dataset.module) {
      state.modules[target.dataset.module] = !state.modules[target.dataset.module];
      render();
      return;
    }
    if (target.dataset.growthGroup) {
      state.growthGroup = target.dataset.growthGroup;
      render();
      return;
    }
    if (target.dataset.growthTab) {
      state.growthTab = target.dataset.growthTab;
      render();
      return;
    }
    if (target.dataset.posture) {
      state.growthDraft.posture = target.dataset.posture;
      render();
      return;
    }
    if (target.dataset.pumpMode) {
      state.pump.mode = target.dataset.pumpMode;
      render();
      return;
    }
    if (target.dataset.pumpSide) {
      state.pump.singleSide = target.dataset.pumpSide;
      render();
      return;
    }
    if (target.dataset.volumeMode) {
      state.pump.volumeMode = target.dataset.volumeMode;
      render();
      return;
    }
    if (target.dataset.feedType) {
      state.bottleFeed.type = target.dataset.feedType;
      render();
      return;
    }
    if (target.dataset.amount) {
      state.bottleFeed.amount = Math.min(500, Math.max(10, state.bottleFeed.amount + Number(target.dataset.amount)));
      render();
      return;
    }
    if (target.dataset.diaper) {
      state.diaperType = target.dataset.diaper;
      render();
      return;
    }
    if (target.dataset.historyFilter) {
      state.historyFilter = target.dataset.historyFilter;
      render();
      return;
    }

    const action = target.dataset.action;
    if (!action) return;
    switch (action) {
      case "finish-onboarding":
        state.screen = "home";
        state.previous = "module-select";
        render();
        toast(`欢迎来到${state.babyName}的私密空间`);
        break;
      case "reset-prototype":
        state = initialState();
        try { localStorage.removeItem(STORAGE_KEY); } catch (_) { /* noop */ }
        render();
        toast("原型已重置");
        break;
      case "show-policy": toast("原型说明：正式版将打开完整儿童信息处理规则"); break;
      case "cloud-info": toast("私密云空间未开启；当前数据仅保存在本机"); break;
      case "export-info": toast("可分别导出宝宝记录、用品追溯和本人吸奶数据"); break;
      case "settings-info": toast("隐私与设置将在开发阶段继续细化"); break;
      case "about": toast("Mom-Baby MVP 高保真交互原型 · v0.3"); break;
      case "manual-record": toast("手工补录仅用于过去记录和计时纠错"); break;
      case "timer-help": toast("退出页面或锁屏后，计时仍按系统时间继续"); break;
      case "capture-tip": toast("请避免反光，并让文字与码完整落在取景框内"); break;
      case "edit-detail": toast("详情编辑会保留原始计时分段与更新时间"); break;
      case "delete-demo": toast("原型未实际删除；正式版删除后会重新计算今日汇总"); break;
      case "nursing-start": {
        if (state.nursing.active) {
          go("nursing-running");
          toast("已继续当前亲喂计时");
          break;
        }
        const side = target.dataset.side || "left";
        const now = Date.now();
        state.nursing = { id:makeId("nursing"), active:true, currentSide:side, paused:false, leftBase:0, rightBase:0, tickAt:now, endedAt:0, startedAt:now, segments:[{ side, startedAt:now, endedAt:0 }] };
        go("nursing-running");
        break;
      }
      case "nursing-switch": {
        const now = Date.now();
        freezeNursing(now);
        const oldSide = state.nursing.currentSide;
        state.nursing.currentSide = oldSide === "left" ? "right" : "left";
        state.nursing.paused = false;
        state.nursing.tickAt = now;
        state.nursing.segments.push({ side:state.nursing.currentSide, startedAt:now, endedAt:0 });
        render();
        toast(`已切到${state.nursing.currentSide === "left" ? "左" : "右"}侧`);
        break;
      }
      case "nursing-pause":
        if (state.nursing.paused) {
          const now = Date.now();
          state.nursing.paused = false;
          state.nursing.tickAt = now;
          state.nursing.segments.push({ side:state.nursing.currentSide, startedAt:now, endedAt:0 });
          toast("计时已继续");
        } else {
          freezeNursing();
          state.nursing.paused = true;
          toast("已暂停，暂停时间不会累计");
        }
        render();
        break;
      case "nursing-end": {
        const now = Date.now();
        freezeNursing(now);
        state.nursing.active = false;
        state.nursing.paused = false;
        state.nursing.endedAt = now;
        const total = state.nursing.leftBase + state.nursing.rightBase;
        addEventOnce(state.nursing.id, { id:makeId("event"), type:"nursing", occurredAt:state.nursing.startedAt, tone:"", title:`亲喂 · ${formatDuration(total,true)}`, subtitle:"成人侧别明细仅本人可见", time:formatClock(state.nursing.startedAt), ago:"刚刚" });
        go("nursing-detail");
        break;
      }
      case "pump-start": {
        if (state.pump.active) {
          go("pump-running");
          toast("已继续当前吸奶计时");
          break;
        }
        const now = Date.now();
        const sides = selectedPumpSides(state.pump);
        state.pump = { ...state.pump, id:makeId("pump"), active:true, leftBase:0, rightBase:0, leftTick:sides.includes("left") ? now : 0, rightTick:sides.includes("right") ? now : 0, leftStartedAt:sides.includes("left") ? now : 0, rightStartedAt:sides.includes("right") ? now : 0, leftEndedAt:0, rightEndedAt:0, leftEnded:!sides.includes("left"), rightEnded:!sides.includes("right"), leftVolume:sides.includes("left") ? 70 : 0, rightVolume:sides.includes("right") ? 65 : 0, startedAt:now, endedAt:0 };
        go("pump-running");
        break;
      }
      case "pump-end-side": {
        const side = target.dataset.side;
        freezePumpSide(side, Date.now());
        state.pump[side === "left" ? "leftEnded" : "rightEnded"] = true;
        render();
        toast(`${side === "left" ? "左" : "右"}侧已结束${pumpFinished(state.pump) ? "" : "，另一侧继续计时"}`);
        break;
      }
      case "pump-finish": {
        const now = Date.now();
        const sides = selectedPumpSides(state.pump);
        sides.forEach((side) => {
          const endedKey = side === "left" ? "leftEnded" : "rightEnded";
          if (!state.pump[endedKey]) { freezePumpSide(side, now); state.pump[endedKey] = true; }
        });
        state.pump.active = false;
        state.pump.endedAt = Math.max(...sides.map((side) => state.pump[`${side}EndedAt`] || now));
        go("pump-volume");
        break;
      }
      case "pump-save":
        addEventOnce(state.pump.id, { id:makeId("event"), type:"pump", occurredAt:state.pump.startedAt, tone:"blue", title:`吸奶 · ${Number(state.pump.leftVolume)+Number(state.pump.rightVolume)} ml`, subtitle:"本人私密记录 · 不计入宝宝喂养", time:formatClock(state.pump.startedAt), ago:"刚刚" });
        go("pump-detail");
        break;
      case "capture-photo":
        state.capture[target.dataset.capture] = true;
        render();
        toast("照片已保存为原型示意图");
        break;
      case "save-formula-can":
        state.formulaCan = { ...state.formulaDraft, id:makeId("can"), version:1, openedAt:Date.now() };
        go("bottle-feed");
        toast("奶粉罐已建立，并用于本次喂养");
        break;
      case "bottle-photo": toast("原型已记录奶瓶标识照片占位"); break;
      case "save-bottle":
        state.bottle = { ...state.bottleDraft, id:state.bottle?.id || makeId("bottle"), version:(state.bottle?.version || 0) + 1, createdAt:state.bottle?.createdAt || Date.now() };
        go("bottle-feed");
        toast("奶瓶已建立，并用于本次喂养");
        break;
      case "save-bottle-feed": {
        const occurredAt = Date.now();
        const isFormula = state.bottleFeed.type === "formula";
        const canSnapshot = isFormula && state.formulaCan ? clone(state.formulaCan) : null;
        const bottleSnapshot = state.bottle ? clone(state.bottle) : null;
        const subtitle = isFormula
          ? canSnapshot && bottleSnapshot ? `${canSnapshot.brand} · ${bottleSnapshot.nickname}` : "用品追溯资料待补充"
          : bottleSnapshot ? bottleSnapshot.nickname : "奶瓶待补充";
        addEventOnce(`feed-${occurredAt}`, { id:makeId("event"), type:"bottle", feedType:state.bottleFeed.type, amount:state.bottleFeed.amount, occurredAt, formulaCanId:canSnapshot?.id || null, bottleId:bottleSnapshot?.id || null, formulaCanSnapshot:canSnapshot, bottleSnapshot, tone:"peach", title:`瓶喂 · ${isFormula ? "配方奶" : "母乳"} ${state.bottleFeed.amount} ml`, subtitle, time:formatClock(occurredAt), ago:"刚刚" });
        go("home");
        toast(`${state.bottleFeed.amount} ml 奶瓶喂养已保存`);
        break;
      }
      case "save-diaper": {
        const labels = { wet:"小便", dirty:"大便", both:"小便 + 大便" };
        addEventOnce(`diaper-${Date.now()}`, { type:"diaper", tone:"gold", title:`尿布 · ${labels[state.diaperType]}`, subtitle:"由我记录", time:"刚刚", ago:"" });
        go("home");
        toast("尿布记录已保存");
        break;
      }
      case "save-sleep":
        addEventOnce(`sleep-${Date.now()}`, { type:"sleep", tone:"blue", title:"睡眠 · 正在计时", subtitle:"点击记录可稍后结束", time:"刚刚", ago:"" });
        go("home");
        toast("睡眠计时已开始");
        break;
      case "save-growth":
        state.growthMeasurements.push({ date:state.growthDraft.date, weight:state.growthDraft.weight, length:state.growthDraft.length });
        go("growth");
        toast("成长测量已保存");
        break;
      case "album-pick":
        state.albumDraftPhoto = true;
        render();
        toast("已通过系统照片选择器选择 1 张照片");
        break;
      case "save-photo":
        state.albumPhoto = true;
        state.albumDraftPhoto = false;
        go("album");
        toast("照片已保存到成长时光");
        break;
    }
  }

  function handleInput(event) {
    const target = event.target;
    if (target.dataset.bind) state[target.dataset.bind] = target.value;
    if (target.dataset.bindFeed) state.bottleFeed[target.dataset.bindFeed] = target.value;
    if (target.dataset.bindFormula) state.formulaDraft[target.dataset.bindFormula] = target.value;
    if (target.dataset.bindBottle) state.bottleDraft[target.dataset.bindBottle] = target.value;
    if (target.dataset.bindGrowth) state.growthDraft[target.dataset.bindGrowth] = target.value;
    if (target.dataset.bindPump) {
      if (target.dataset.bindPump === "totalVolume") { state.pump.leftVolume = Number(target.value); state.pump.rightVolume = 0; }
      else state.pump[target.dataset.bindPump] = Number(target.value);
    }
    saveState();
  }

  function configuredState() {
    const s = initialState();
    s.consentGuardian = true;
    s.consentChild = true;
    s.formulaCan = { ...s.formulaDraft, id:"can_example_current", version:1, openedAt:new Date("2026-08-18T09:00:00+08:00").getTime() };
    s.bottle = { ...s.bottleDraft, id:"bottle_example_current", version:1, createdAt:new Date("2026-08-01T09:00:00+08:00").getTime() };
    const sampleFeed = s.events.find((event) => event.feedType === "formula");
    if (sampleFeed) {
      sampleFeed.formulaCanId = s.formulaCan.id;
      sampleFeed.bottleId = s.bottle.id;
      sampleFeed.formulaCanSnapshot = clone(s.formulaCan);
      sampleFeed.bottleSnapshot = clone(s.bottle);
      sampleFeed.subtitle = `${s.formulaCan.brand} · ${s.bottle.nickname}`;
    }
    return s;
  }

  function renderBoard() {
    if (!board) return;
    const base = configuredState();
    const empty = initialState();
    const demoNow = Date.now();
    const nursingLeft = clone(base);
    nursingLeft.nursing = { id:"nursing_board_left",active:true,currentSide:"left",paused:false,leftBase:0,rightBase:0,tickAt:demoNow-492000,endedAt:0,startedAt:demoNow-492000,segments:[{side:"left",startedAt:demoNow-492000,endedAt:0}] };
    const nursingPaused = clone(base);
    nursingPaused.nursing = { id:"nursing_board_paused",active:true,currentSide:"right",paused:true,leftBase:492,rightBase:220,tickAt:0,endedAt:0,startedAt:demoNow-832000,segments:[{side:"left",startedAt:demoNow-832000,endedAt:demoNow-340000},{side:"right",startedAt:demoNow-220000,endedAt:demoNow}] };
    const nursingDone = clone(base);
    nursingDone.nursing = { id:"nursing_board_done",active:false,currentSide:"right",paused:false,leftBase:492,rightBase:220,tickAt:0,endedAt:demoNow,startedAt:demoNow-832000,segments:[{side:"left",startedAt:demoNow-832000,endedAt:demoNow-340000},{side:"right",startedAt:demoNow-220000,endedAt:demoNow}] };
    const pumpRunning = clone(base);
    pumpRunning.pump = { ...pumpRunning.pump,id:"pump_board_running",active:true,mode:"double",leftBase:920,rightBase:0,leftTick:0,rightTick:demoNow-1040000,leftStartedAt:demoNow-1040000,rightStartedAt:demoNow-1040000,leftEndedAt:demoNow-120000,rightEndedAt:0,leftEnded:true,rightEnded:false,startedAt:demoNow-1040000,endedAt:0 };
    const pumpDone = clone(base);
    pumpDone.pump = { ...pumpDone.pump,id:"pump_board_done",active:false,mode:"double",leftBase:920,rightBase:1040,leftTick:0,rightTick:0,leftStartedAt:demoNow-1040000,rightStartedAt:demoNow-1040000,leftEndedAt:demoNow-120000,rightEndedAt:demoNow,leftEnded:true,rightEnded:true,startedAt:demoNow-1040000,endedAt:demoNow };
    const captured = clone(empty);
    captured.capture = { front:true,batch:true,code:true };
    const albumAdded = clone(base);
    albumAdded.albumPhoto = true;
    const photoDraft = clone(base);
    photoDraft.albumDraftPhoto = true;
    const boardItems = [
      ["01","欢迎","首次打开与本地优先承诺","welcome",empty],
      ["02","监护人同意","儿童敏感信息单独同意","consent",base],
      ["03","宝宝建档","最小必要资料","baby-profile",base],
      ["04","模块选择","可按当前阶段精简首页","module-select",base],
      ["05","今日首页","状态、汇总与统一流水","home",base],
      ["06","全局记录","任意一级页面快速添加","quick-add",base],
      ["07","开始亲喂","左右侧一键开始","nursing-start",base],
      ["08","亲喂 · 左侧进行中","系统计时与后台恢复","nursing-running",nursingLeft],
      ["09","亲喂 · 切右后暂停","左右分段与暂停排除","nursing-running",nursingPaused],
      ["10","亲喂详情","宝宝快照与成人明细隔离","nursing-detail",nursingDone],
      ["11","开始吸奶","单边或双边模式","pump-start",base],
      ["12","双边吸奶 · 左侧结束","左右独立结束","pump-running",pumpRunning],
      ["13","填写吸奶量","分侧或只填总量","pump-volume",pumpDone],
      ["14","吸奶详情","成人本人私密记录","pump-detail",pumpDone],
      ["15","瓶喂 · 缺少用品","紧急记录不阻塞", "bottle-feed",empty],
      ["16","奶粉罐空状态","说明三类证据", "formula-empty",empty],
      ["17","拍摄包装","三步拍摄取景状态", "formula-capture-front",empty],
      ["18","核对奶粉资料","OCR 后必须人工确认", "formula-verify",captured],
      ["19","建立奶瓶","基础身份与稳定标识", "bottle-create",base],
      ["20","瓶喂 · 用品已关联","常规记录 10 秒路径", "bottle-feed",base],
      ["21","尿布快记","小便、大便或混合", "diaper-add",base],
      ["22","成长趋势","个人曲线与参考带", "growth",base],
      ["23","相册空态","本机私密与照片选择", "album",empty],
      ["24","相册已添加","按日期与月龄整理", "album",albumAdded],
      ["25","添加成长照片","渐进填写说明", "album-add",photoDraft],
      ["26","全部历史","跨模块统一时间线", "history",base],
      ["27","我的","空间与数据控制入口", "me",base],
      ["28","用品档案","奶粉罐与奶瓶复用", "supplies",base]
    ];
    board.innerHTML = boardItems.map(([number,title,caption,screen,s]) => `<article class="board-item"><div class="board-caption"><span class="board-number">${number}</span><div><strong>${title}</strong><span>${caption}</span></div></div><div class="board-phone"><div class="app-root">${screenMarkup(screen,s)}</div></div></article>`).join("");
  }

  if (board) {
    renderBoard();
  } else if (app) {
    loadState();
    render();
    document.addEventListener("click", handleClick);
    document.addEventListener("input", handleInput);
    document.addEventListener("keydown", (event) => {
      if (event.key.toLowerCase() === "r" && !/input|textarea/i.test(document.activeElement.tagName)) {
        state.screen = "welcome";
        render();
      }
    });
    setInterval(updateLiveTimers, 1000);
  }
})();
