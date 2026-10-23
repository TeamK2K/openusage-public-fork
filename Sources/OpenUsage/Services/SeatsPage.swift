import Foundation

/// The concise "which account has room" page the local server serves at `/`. A top bar (title, Add
/// Account), then one card per account, all fitted on one screen, named by its email and headed by what
/// is left before its reset and how long until that reset, then a status and its session / weekly (or
/// monthly) / Fable bars. Every time on it is relative ("in 2d 4h"). Cards run soonest reset first,
/// because room left at a reset is lost; the first one is named on top and outlined. It reads
/// `/v1/limits` and `/v1/accounts/signin` from the same origin and refreshes itself, so it needs nothing
/// beyond the running app. Self-contained: no external assets. The sign-in script is `SeatsPageSignIn`.
enum SeatsPage {
    static let html: Data = Data((source + SeatsPageSignIn.source).utf8)

    private static let source = #"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>AI accounts · OpenUsage</title>
<style>
:root { --bg:#f4f4f1; --card:#fff; --text:#1c1c1a; --muted:#6e6d68; --faint:#9c9b95; --line:#e4e3de; --track:#e9e8e3;
        --bar:#2f7de1; --warn:#b97c0c; --out:#d13f3f; --ok:#23915a; }
@media (prefers-color-scheme: dark) {
  :root { --bg:#111110; --card:#1b1b1a; --text:#edece6; --muted:#a3a29b; --faint:#6f6e69; --line:#2a2a27; --track:#2e2e2b;
          --bar:#4d96f2; --warn:#e3a43c; --out:#f06868; --ok:#52c886; }
}
* { box-sizing: border-box; }
[hidden] { display:none !important; }
html { font-size: clamp(14px, 0.4vw + 0.4vh + 6px, 22px); }
body { margin:0; background:var(--bg); color:var(--text);
       font: 1rem/1.4 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; }
/* One screen, no scrolling: header, a card grid that takes the rest, a one-line footer. */
main { height:100svh; display:flex; flex-direction:column; gap:.9rem; padding: clamp(14px, 2.2vw, 40px); }
.top { display:flex; flex-wrap:wrap; align-items:baseline; column-gap:1.2rem; row-gap:.2rem; }
.bar { flex-basis:100%; display:flex; justify-content:space-between; align-items:center; gap:1rem; margin-bottom:.2rem; }
.bar .title { font-size:.8rem; font-weight:650; color:var(--muted); letter-spacing:.06em; text-transform:uppercase; }
.top h1 { margin:0; font-size:1.75rem; line-height:1.15; font-weight:650; letter-spacing:-.01em; overflow-wrap:anywhere; }
.top h1 .dim { color:var(--muted); font-weight:500; }
.top .sub { margin:0; color:var(--muted); }
.error { flex-basis:100%; margin:.3rem 0 0; color:var(--out); }
.btn { font:inherit; font-size:.85rem; font-weight:600; line-height:1.3; color:var(--text); background:var(--card);
       border:1px solid var(--line); border-radius:8px; padding:.3rem .8rem; cursor:pointer; text-decoration:none; white-space:nowrap; }
.btn.primary { background:var(--bar); border-color:var(--bar); color:#fff; }
.btn:disabled { opacity:.5; cursor:default; }
.add { position:relative; }
.menu { position:absolute; right:0; top:calc(100% + .3rem); z-index:2; display:flex; flex-direction:column; gap:.25rem; padding:.35rem;
        min-width:8rem; background:var(--card); border:1px solid var(--line); border-radius:10px; box-shadow:0 6px 20px rgba(0,0,0,.14); }
.menu .btn { text-align:left; border-color:transparent; }
/* The sign-in panel: waiting, the paste box, and how it ended. */
.signin { display:flex; flex-wrap:wrap; align-items:center; gap:.5rem .8rem; padding:.6rem .9rem; font-size:.9rem;
          background:var(--card); border:1px solid var(--bar); border-radius:12px; }
.signin.failed { border-color:var(--out); }
.signin.failed #siTitle { color:var(--out); }
.signin .sitext { flex:1 1 18rem; min-width:0; }
.signin .sidetail { color:var(--muted); }
.signin .notice { color:var(--warn); }
.signin form { display:flex; gap:.4rem; flex:1 1 22rem; min-width:0; }
.signin input { flex:1; min-width:0; font:inherit; padding:.3rem .6rem; color:var(--text); background:var(--bg);
                border:1px solid var(--line); border-radius:8px; }
#cards { flex:1; min-height:0; display:grid; gap: clamp(8px, 1vw, 18px);
         grid-template-columns: repeat(var(--cols, 3), minmax(0, 1fr)); grid-template-rows: repeat(var(--rows, 3), minmax(0, 1fr)); }
.card { min-width:0; min-height:0; overflow:hidden; background:var(--card); border:1px solid var(--line); border-radius:14px; }
.card.best { border-color:var(--bar); box-shadow: inset 0 0 0 1px var(--bar); }
.card.stale, .card.down .in > :not(.signrow) { opacity:.55; }
/* Everything inside is sized in em off one font size, which fit() picks per screen so that no card
   wraps, cuts off or clips a line. */
.in { height:100%; display:flex; flex-direction:column; gap:.55em; padding:.85em .95em; font-size:var(--fs, 14px); }
.who { min-width:0; }
.mid { display:flex; justify-content:space-between; align-items:flex-end; gap:.6em; }
.krow { display:flex; align-items:center; gap:.6em; min-width:0; }
.krow .kicker { flex:1; min-width:0; }
/* On the account whose usage went up in the last 15 minutes: the one being used right now. */
.inuse { flex:none; font-size:.68em; font-weight:700; letter-spacing:.05em; text-transform:uppercase; color:var(--bar);
         border:1px solid var(--bar); border-radius:999px; padding:0 .6em; line-height:1.25; }
.kicker { font-size:.72em; line-height:1.3; color:var(--faint); letter-spacing:.05em; text-transform:uppercase; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
/* The account's email is its name: never cut off, it wraps at the @ onto a second line instead. */
.name { font-size:1.1em; font-weight:650; line-height:1.15; overflow-wrap:anywhere; overflow:hidden;
        display:-webkit-box; -webkit-line-clamp:2; -webkit-box-orient:vertical; }
.extras { font-size:.78em; color:var(--muted); margin-top:.15em; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.room { flex:none; font-size:2.4em; font-weight:700; line-height:1; font-variant-numeric: tabular-nums; }
.room small { display:block; font-size:.3em; font-weight:500; color:var(--faint); letter-spacing:.05em; margin-top:.3em; }
.room.warn, .status.warn { color:var(--warn); } .room.out, .status.out { color:var(--out); }
.side { flex:1; min-width:0; display:flex; flex-direction:column; align-items:flex-end; gap:.25em; text-align:right; padding-bottom:1em; }
.resetin { max-width:100%; font-size:.95em; font-weight:650; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
/* A status is always one line: the dot stays, the text never wraps. */
.status { font-size:.8em; font-weight:600; color:var(--ok); display:flex; align-items:center; justify-content:flex-end; gap:.45em; max-width:100%; white-space:nowrap; }
.status span:not(.dot) { min-width:0; overflow:hidden; text-overflow:ellipsis; }
.dot { width:.55em; height:.55em; border-radius:50%; background:currentColor; flex:none; }
/* The limits follow the headline with normal spacing, so a card with one or two bars has no gap. */
.bars { display:flex; flex-direction:column; gap:.5em; }
/* A remembered account with no login: its message stands where the bars would be. */
.downmsg { color:var(--muted); font-size:.9em; overflow-wrap:anywhere; overflow:hidden;
           display:-webkit-box; -webkit-line-clamp:5; -webkit-box-orient:vertical; }
.signrow { margin-top:auto; }
.signrow .btn { font-size:.85em; }
.meter { display:grid; grid-template-columns: auto 1fr auto; column-gap:.5em; row-gap:.25em; align-items:baseline; }
.meter .lbl { font-size:.8em; color:var(--muted); }
.when { min-width:0; font-size:.72em; color:var(--faint); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.when.out { color:var(--out); }
.pct { font-size:.85em; color:var(--muted); font-variant-numeric: tabular-nums; }
.pct.out { color:var(--out); }
/* Battery bars: ten cells per limit, each worth 10%, the last one filled part-way. */
.cells { grid-column: 1 / -1; display:grid; grid-template-columns:repeat(10, 1fr); gap:.2em; }
.cell { height:.7em; border-radius:.18em; background:linear-gradient(to right, var(--c) var(--f), var(--track) var(--f)); }
.cells.ok { --c:var(--bar); } .cells.warn { --c:var(--warn); } .cells.out { --c:var(--out); }
.empty { color:var(--muted); }
.foot { display:flex; flex-wrap:wrap; gap:.3rem 1.2rem; font-size:.8rem; color:var(--faint); }
.issues { color:var(--warn); }
/* Phones: one card per row at a fixed height, and the page scrolls. */
@media (max-width: 640px) {
  main { height:auto; min-height:100svh; }
  #cards { display:flex; flex-direction:column; }
  .card { height:auto; flex:none; }
  .in { font-size:15px; gap:.9em; padding:1em 1.1em; }
  .bars { gap:.7em; }
  .top h1 { font-size:1.45rem; }
}
</style>
</head>
<body>
<main>
  <header class="top">
    <div class="bar">
      <span class="title">AI Accounts</span>
      <div class="add">
        <button class="btn primary" id="addBtn" type="button" aria-haspopup="true" aria-expanded="false">Add Account</button>
        <div class="menu" id="addMenu" hidden>
          <button class="btn" type="button" data-tool="claude">Claude</button>
          <button class="btn" type="button" data-tool="codex">Codex</button>
        </div>
      </div>
    </div>
    <h1 id="verdict">Loading…</h1>
    <p class="sub" id="sub"></p>
    <p class="error" id="error" hidden>OpenUsage isn't answering on this Mac. Open the OpenUsage menu bar app, then this page refreshes by itself.</p>
  </header>
  <section class="signin" id="signin" hidden>
    <div class="sitext"><strong id="siTitle"></strong> <span class="sidetail" id="siDetail"></span> <span class="notice" id="siNotice"></span></div>
    <a class="btn" id="siLink" target="_blank" rel="noopener" hidden>Open Sign-In Page</a>
    <form id="siForm" hidden>
      <input id="siCode" autocomplete="off" spellcheck="false" aria-label="Sign-in code" placeholder="Paste the code, or the address of a page that didn't load">
      <button class="btn primary" type="submit">Paste Code</button>
    </form>
    <button class="btn" id="siCancel" type="button" hidden>Cancel</button>
    <button class="btn" id="siClose" type="button" hidden>Close</button>
  </section>
  <div id="cards"></div>
  <div class="foot"><span id="footer"></span><span class="issues" id="issues" hidden></span></div>
</main>
<script>
const REFRESH_MS = 30000;

// <time-format> Every time on this page is relative, in one format: "in 45m", "in 2h 29m", "in 6d 2h",
// "in 13d". Minutes go once it is a day or more away, hours once it is ten days or more away. No clock
// times or dates, so a card's lines stay short enough never to wrap.
function left(ms) {
  if (ms <= 0) return "now";
  if (ms >= 86400000) {
    const hours = Math.round(ms / 3600000), d = Math.floor(hours / 24), h = hours % 24;
    return d >= 10 ? Math.round(ms / 86400000) + "d" : d + "d" + (h ? " " + h + "h" : "");
  }
  const m = Math.max(1, Math.round(ms / 60000)), h = Math.floor(m / 60), r = m % 60;
  return h ? h + "h" + (r ? " " + r + "m" : "") : r + "m";
}
function when(ms) {
  const diff = ms - Date.now();
  return diff <= 0 ? "now" : "in " + left(diff);
}
// </time-format>

function pct(r) { return r && typeof r.remaining === "number" ? Math.max(0, Math.min(100, Math.round(r.remaining))) : null; }
function label(id, p) {
  const raw = (p.displayName || id).replace(/'s Organization$/, "");
  const m = raw.match(/^Claude\s*[—:–-]\s*(.+)$/);
  return m ? { family: "Claude", detail: m[1] } : { family: raw, detail: p.plan || "" };
}
function el(tag, cls, text) { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }

// Reset time for one bar: "resets in 2h 7m"; "back in …" in red when that limit is used up; "not
// started" when a window has no clock running yet.
function resetText(res, value) {
  if (!res) return "";
  if (!res.resetsAt) return value != null && value >= 100 ? "not started" : "";
  return (value === 0 ? "back " : "resets ") + when(new Date(res.resetsAt).getTime());
}
// When a window is on pace to hit 100% before it resets, else null. Needs a tenth of the window
// elapsed so an early spike does not raise a false alarm.
function runOut(name, res, now) {
  if (!res || !res.resetsAt || !(res.windowSeconds > 0) || !(res.used > 0)) return null;
  const resetMs = new Date(res.resetsAt).getTime();
  const elapsed = res.windowSeconds - (resetMs - now) / 1000;
  if (!(elapsed / res.windowSeconds >= 0.1)) return null;
  const fullMs = now + Math.max(0, 100 - res.used) * elapsed / res.used * 1000;
  return fullMs < resetMs ? { name, fullMs, resetMs } : null;
}
function money(n) { return "$" + Math.round(n).toLocaleString(); }
function amount(res) { return res && typeof res.available === "number" ? res.available : 0; }
// Small second line under the account: reset passes and extra credit, each hidden at zero.
function extras(r) {
  const out = [];
  const passes = amount(r.rateLimitResets);
  if (passes > 0) {
    const exp = r.rateLimitResets.expiresAt;
    const first = (Array.isArray(exp) ? exp : []).map(x => new Date(x).getTime()).filter(t => !isNaN(t)).sort((a, b) => a - b)[0];
    out.push(passes + (passes === 1 ? " reset pass" : " reset passes") +
      (first ? (passes === 1 ? ", expires " : ", first expires ") + when(first) : ""));
  }
  for (const key of ["extraUsage", "onDemand"]) {
    const x = r[key];
    if (x && x.unit === "usd" && x.limit > 0 && x.remaining > 0) out.push(money(x.remaining) + " of " + money(x.limit) + " extra left");
  }
  if (amount(r.extraUsageBalance) > 0 && r.extraUsageBalance.unit === "usd") out.push(money(r.extraUsageBalance.available) + " extra");
  const credits = amount(r.credits), value = r.creditValue && r.creditValue.unit === "usd" ? amount(r.creditValue) : 0;
  if (credits > 0) out.push(credits.toLocaleString() + " credits" + (value > 0 ? " (~" + money(value) + ")" : ""));
  else if (value > 0) out.push(money(value) + " credit");
  return out;
}

function title(key) { return key.replace(/([A-Z])/g, " $1").replace(/^./, c => c.toUpperCase()); }

function toRow(id, p) {
  const r = p.resources || {};
  const session = r.session, long = r.weekly || r.totalUsage, fable = r.fable;
  const longName = long && long.windowSeconds > 8 * 86400 ? "Monthly" : "Weekly";
  // The week (or month) leads: it is the limit whose leftover a reset throws away.
  let bars = [[longName, long], ["Session", session], ["Fable", fable]].filter(([, res]) => res);
  // An account with other limits only (Copilot's chat and completions): show each percent limit.
  if (!session && !long) {
    bars = Object.entries(r).filter(([, res]) => res && res.unit === "percent" && typeof res.remaining === "number")
      .map(([key, res]) => [title(key), res]);
  }
  if (!bars.length) return null;
  bars = bars.map(([name, res]) => ({ name, res, value: pct(res) }));
  const score = Math.min(...bars.map(b => b.value ?? 100));
  let note = "Ready", out = false, warn = false, noteTitle = "", backMs = null;
  const now = Date.now();
  const soon = bars.map(b => runOut(b.name, b.res, now)).filter(Boolean).sort((a, b) => a.fullMs - b.fullMs)[0];
  const blocked = bars.filter(b => b.value === 0);
  if (blocked.length) {
    out = true;
    const latest = blocked.map(b => b.res.resetsAt).filter(Boolean).sort().pop();
    note = latest ? "Back " + when(new Date(latest).getTime()) : "Out of room";
    backMs = latest ? new Date(latest).getTime() : null;
  } else if (soon) {
    warn = true;
    note = "Runs out " + when(soon.fullMs);
    noteTitle = soon.name + " on pace to run out " + when(soon.fullMs) + ", before it resets " + when(soon.resetMs);
  }
  // The room a reset throws away: the tightest limit other than the 5-hour session (the week's or
  // the month's), and when it resets. The card's headline and the use-first order read these.
  const longBars = bars.filter(b => b.name !== "Session");
  const tight = (longBars.length ? longBars : bars).reduce((a, b) => ((b.value ?? 100) < (a.value ?? 100) ? b : a));
  const leftover = tight.value ?? 100;
  const resetMs = tight.res.resetsAt ? new Date(tight.res.resetsAt).getTime() : null;
  const low = bars.reduce((a, b) => ((b.value ?? 100) < (a.value ?? 100) ? b : a)).name;
  return { id, p, bars, score, leftover, resetMs, low, backMs, note, noteTitle, warn, out, extras: extras(r),
           isClaude: id.startsWith("claude") };
}

// Use-first order: the account whose room resets soonest goes first, because room left at a reset
// is lost. Accounts under 10% come after the rest, and accounts at a limit last, soonest back first.
function rank(x) { return x.down ? 3 : x.out ? 2 : x.score < 10 ? 1 : 0; }
function byUseFirst(a, b) {
  const at = a.out ? a.backMs : a.resetMs, bt = b.out ? b.backMs : b.resetMs;
  return rank(a) - rank(b) || (at ?? Infinity) - (bt ?? Infinity) || b.leftover - a.leftover;
}

// In use: the app saw this account's usage go up within the last 15 minutes (about three refreshes),
// so a session is running on it now — whichever account the page recommends.
const IN_USE_MS = 15 * 60000;
function inUse(p) { return !!p.usageRoseAt && Date.now() - new Date(p.usageRoseAt) <= IN_USE_MS; }

// An account goes by its email (Claude) or, where the app has no email, its product name.
function accountName(x) { const n = label(x.id, x.p); return x.isClaude ? n.detail : n.family; }
function nameEl(text) {
  const e = el("div", "name"), at = text.indexOf("@");
  if (at > 0) e.append(text.slice(0, at), document.createElement("wbr"), text.slice(at));
  else e.textContent = text;
  return e;
}

// How a card reads: out (a limit at 0), warn (on pace to run out, or under 25% left), else ready.
function tone(x) { return x.out ? "out" : (x.warn || x.score < 25) ? "warn" : "ok"; }

function meter(value, name, res) {
  const box = el("div", "meter");
  const when = resetText(res, value);
  box.append(el("span", "lbl", name), el("span", "when" + (value === 0 ? " out" : ""), when),
    el("span", "pct" + (value === 0 ? " out" : ""), value == null ? "–" : value + "%"));
  const cells = el("div", "cells " + (value === 0 ? "out" : value != null && value < 25 ? "warn" : "ok"));
  for (let i = 0; i < 10; i++) {
    const cell = el("span", "cell");
    cell.style.setProperty("--f", (value == null ? 0 : Math.max(0, Math.min(1, (value - i * 10) / 10)) * 100) + "%");
    cells.appendChild(cell);
  }
  box.appendChild(cells);
  return box;
}

// Headline: what is left before the reset and how long until it ("91% left · resets in 3d 20h"),
// then a status: Back in … / Runs out in … / <limit> low / Use this one / Ready.
function card(x, isBest) {
  const t = tone(x);
  const box = el("div", "card" + (isBest ? " best" : "") + (x.p.stale ? " stale" : "") + (x.down ? " down" : ""));
  const inner = el("div", "in");
  const who = el("div", "who");
  const kicker = [x.isClaude ? "Claude" : "", x.p.plan || ""].filter(Boolean).join(" · ");
  const krow = el("div", "krow");
  krow.appendChild(el("div", "kicker", kicker || " "));
  if (x.down) {
    // An account the app remembers but cannot read right now (signed out): its message, no bars, and
    // a Sign In button when the app can sign it back in.
    who.append(krow, nameEl(accountName(x)));
    inner.append(who, el("div", "downmsg", x.message));
    const row = signInRow(x.id);
    if (row) inner.appendChild(row);
    box.appendChild(inner);
    return box;
  }
  if (inUse(x.p)) {
    const badge = el("span", "inuse", "In use");
    badge.title = "Usage seen going up " + left(Date.now() - new Date(x.p.usageRoseAt)) + " ago: a session is running on this account";
    krow.appendChild(badge);
  }
  who.append(krow, nameEl(accountName(x)));
  who.title = (x.p.displayName || x.id) + (x.p.plan ? " · " + x.p.plan : "");
  if (x.extras.length) who.appendChild(el("div", "extras", x.extras.join(" · ")));
  const room = el("div", "room " + (x.out ? "out" : x.warn || x.leftover < 25 ? "warn" : "ok"), x.leftover + "%");
  room.appendChild(el("small", null, "LEFT"));
  const side = el("div", "side");
  if (!x.out && x.resetMs) side.appendChild(el("div", "resetin", "resets " + when(x.resetMs)));
  const status = el("div", "status " + t);
  status.append(el("span", "dot"), el("span", null, x.out || x.warn ? x.note : isBest ? "Use this one" : x.score < 25 ? x.low + " low" : "Ready"));
  side.appendChild(status);
  const mid = el("div", "mid");
  mid.append(room, side);
  if (x.noteTitle) status.title = x.noteTitle;
  const bars = el("div", "bars");
  for (const b of x.bars) bars.appendChild(meter(b.value, b.name, b.res));
  inner.append(who, mid, bars);
  box.appendChild(inner);
  return box;
}

// Fit every card on one screen at the biggest font that leaves nothing cut off: for each column count,
// search the font size at which no card clips, wraps a one-line field or cuts its name, and keep the
// column count that allows the biggest one. Measured, not estimated, so it holds for any card mix.
const MIN_FS = 8, MAX_FS = 26;
function overflowing(grid) {
  for (const c of grid.children) {
    const box = c.firstElementChild;
    if (box.scrollHeight > box.clientHeight + 1 || box.scrollWidth > box.clientWidth + 1) return true;
    for (const e of c.querySelectorAll(".name, .resetin, .status span, .when, .downmsg"))
      if (e.scrollWidth > e.clientWidth + 1 || e.scrollHeight > e.clientHeight + 1) return true;
  }
  return false;
}
function fit() {
  const grid = document.getElementById("cards"), n = grid.children.length;
  if (!n) return;
  if (matchMedia("(max-width: 640px)").matches) { grid.style.removeProperty("--fs"); return; }
  const set = (cols, fs) => {
    grid.style.setProperty("--cols", cols);
    grid.style.setProperty("--rows", Math.ceil(n / cols));
    grid.style.setProperty("--fs", fs + "px");
  };
  let best = null;
  for (let cols = 1; cols <= n && !(best && best.fs >= MAX_FS); cols++) {
    let lo = best ? best.fs + 0.25 : MIN_FS, hi = MAX_FS;
    set(cols, lo);
    if (overflowing(grid)) continue;
    set(cols, hi);
    if (!overflowing(grid)) lo = hi;
    while (hi - lo > 0.25) {
      const mid = (lo + hi) / 2;
      set(cols, mid);
      if (overflowing(grid)) hi = mid; else lo = mid;
    }
    best = { cols, fs: lo };
  }
  // Nothing fits even at the smallest size (a tiny window): the smallest size, about square.
  if (!best) best = { cols: Math.min(n, Math.ceil(Math.sqrt(n * 1.5))), fs: MIN_FS };
  set(best.cols, best.fs);
}
new ResizeObserver(fit).observe(document.getElementById("cards"));

// An account with an error and no data at all (signed out): a card of its own, with the message.
function downRow(e) {
  const name = e.displayName || e.providerId;
  return { id: e.providerId, p: { displayName: name, plan: "" }, down: true, message: e.message || "Couldn't refresh",
           bars: [], out: false, score: 0, leftover: 0, resetMs: null, backMs: null, extras: [],
           isClaude: e.providerId.startsWith("claude") };
}

function render(data) {
  const providers = data.providers || {};
  const errors = data.errors || [];
  const rows = Object.entries(providers).map(([id, p]) => toRow(id, p)).filter(Boolean)
    .concat(errors.filter(e => !providers[e.providerId]).map(downRow)).sort(byUseFirst);
  const verdict = document.getElementById("verdict"), sub = document.getElementById("sub");
  verdict.textContent = ""; sub.textContent = "";
  const live = rows.filter(x => !x.down);
  const best = live.find(x => !x.out);
  if (!rows.length) {
    verdict.textContent = "No accounts yet";
    sub.textContent = "Add an account above, or turn providers on in the OpenUsage menu bar app.";
  } else if (best) {
    const at = best.resetMs ? ", resets " + when(best.resetMs) : "";
    verdict.append("Use ", accountName(best), el("span", "dim", " · " + best.leftover + "% left" + at));
    const ready = live.filter(x => !x.out).length;
    sub.textContent = ready + " of " + rows.length + " accounts ready · soonest reset first, because room left at a reset is lost";
  } else if (live.length) {
    const first = live.map(x => x.backMs).filter(Boolean).sort((a, b) => a - b)[0];
    verdict.textContent = "Every account is out";
    sub.textContent = first ? "First one back " + when(first) : "No reset time reported yet";
  } else {
    verdict.textContent = "No account is signed in";
    sub.textContent = "Sign in to an account, then this page refreshes by itself.";
  }
  const grid = document.getElementById("cards");
  grid.textContent = "";
  for (const x of rows) grid.appendChild(card(x, x === best));
  fit();
  // Accounts whose last refresh failed: their card (if any) shows older numbers, so say which.
  // A signed-out account is a card of its own that already says so.
  const failed = errors.filter(e => providers[e.providerId]).map(e => {
    const p = providers[e.providerId];
    return (p && p.displayName || e.providerId) + (e.message ? " (" + e.message + ")" : "");
  });
  const issues = document.getElementById("issues");
  issues.hidden = !failed.length;
  issues.textContent = failed.length ? "Couldn't refresh: " + failed.join(" · ") : "";
  // The oldest numbers on screen, not the time of this request: a stalled account shows its real age.
  const oldest = rows.map(x => x.p.fetchedAt).filter(Boolean).sort()[0];
  const age = oldest ? Date.now() - new Date(oldest).getTime() : null;
  document.getElementById("footer").textContent =
    (age == null ? "No data yet" : "Data from " + (age < 60000 ? "just now" : left(age) + " ago")) + " · refreshes every 30 seconds";
}

async function refresh() {
  try {
    const [res] = await Promise.all([fetch("/v1/limits", { cache: "no-store" }), loadSignIn()]);
    if (!res.ok) throw new Error(res.status);
    render(await res.json());
    document.getElementById("error").hidden = true;
  } catch (e) {
    document.getElementById("error").hidden = false;
  }
}
</script>
"""#
}
