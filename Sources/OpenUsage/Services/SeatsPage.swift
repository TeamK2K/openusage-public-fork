import Foundation

/// The concise "which account has room" page the local server serves at `/`. One card per account,
/// all fitted on one screen, named by its email and headed by what is left before its reset and when
/// that reset comes, then a status and its session / weekly (or monthly) / Fable bars. Cards run
/// soonest reset first, because room left at a reset is lost; the first one is named on top and outlined. It reads `/v1/limits` from the same origin and
/// refreshes itself, so it needs nothing beyond the running app. Self-contained: no external assets.
enum SeatsPage {
    static let html: Data = Data(source.utf8)

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
html { font-size: clamp(14px, 0.4vw + 0.4vh + 6px, 22px); }
body { margin:0; background:var(--bg); color:var(--text);
       font: 1rem/1.4 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; }
/* One screen, no scrolling: header, a card grid that takes the rest, a one-line footer. */
main { height:100svh; display:flex; flex-direction:column; gap:1.1rem; padding: clamp(14px, 2.2vw, 40px); }
.top { display:flex; flex-wrap:wrap; align-items:baseline; column-gap:1.2rem; row-gap:.2rem; }
.top h1 { margin:0; font-size:1.75rem; line-height:1.15; font-weight:650; letter-spacing:-.01em; overflow-wrap:anywhere; }
.top h1 .dim { color:var(--muted); font-weight:500; }
.top .sub { margin:0; color:var(--muted); }
.error { flex-basis:100%; margin:.3rem 0 0; color:var(--out); }
#cards { flex:1; min-height:0; display:grid; gap: clamp(8px, 1vw, 18px);
         grid-template-columns: repeat(var(--cols, 3), minmax(0, 1fr)); grid-template-rows: repeat(var(--rows, 3), minmax(0, 1fr)); }
.card { container-type:size; min-width:0; min-height:0; overflow:hidden; background:var(--card);
        border:1px solid var(--line); border-radius:14px; }
.card.best { border-color:var(--bar); box-shadow: inset 0 0 0 1px var(--bar); }
.card.stale { opacity:.55; }
/* Everything inside scales with the card, so a 4-card and a 9-card screen both read cleanly. */
.in { height:100%; display:flex; flex-direction:column; gap:3.2cqh; padding: 5.5cqmin 6cqmin;
      font-size: clamp(10px, min(5.4cqh, 6.4cqw), 26px); }
.who { min-width:0; }
.mid { display:flex; justify-content:space-between; align-items:flex-end; gap:.8em; }
.krow { display:flex; align-items:center; gap:.6em; min-width:0; }
.krow .kicker { flex:1; min-width:0; }
/* On the account whose usage went up in the last 15 minutes: the one being used right now. */
.inuse { flex:none; font-size:.68em; font-weight:700; letter-spacing:.05em; text-transform:uppercase; color:var(--bar);
         border:1px solid var(--bar); border-radius:999px; padding:0 .6em; line-height:1.25; }
.kicker { font-size:.72em; color:var(--faint); letter-spacing:.05em; text-transform:uppercase; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
/* The account's email is its name: never cut off, it wraps at the @ onto a second line instead. */
.name { font-size:1.2em; font-weight:650; line-height:1.15; overflow-wrap:anywhere; overflow:hidden;
        display:-webkit-box; -webkit-line-clamp:2; -webkit-box-orient:vertical; }
.extras { font-size:.78em; color:var(--muted); margin-top:.15em; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.room { flex:none; font-size:2.9em; font-weight:700; line-height:1; font-variant-numeric: tabular-nums; }
.room small { display:block; font-size:.3em; font-weight:500; color:var(--faint); letter-spacing:.05em; margin-top:.3em; }
.room.warn, .status.warn { color:var(--warn); } .room.out, .status.out { color:var(--out); }
.side { flex:1; min-width:0; display:flex; flex-direction:column; align-items:flex-end; gap:.3em; text-align:right; padding-bottom:1.1em; }
.resetin { font-size:1.05em; font-weight:650; text-wrap:balance; }
.status { font-size:.85em; font-weight:600; color:var(--ok); display:flex; align-items:center; gap:.45em; }
.dot { width:.55em; height:.55em; border-radius:50%; background:currentColor; flex:none; }
.bars { margin-top:auto; display:flex; flex-direction:column; gap:2.6cqh; }
.meter { display:grid; grid-template-columns: auto 1fr auto; column-gap:.5em; row-gap:.3em; align-items:baseline; }
.meter .lbl { font-size:.8em; color:var(--muted); }
.when { font-size:.72em; color:var(--faint); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.when.out { color:var(--out); }
.pct { font-size:.85em; color:var(--muted); font-variant-numeric: tabular-nums; }
.pct.out { color:var(--out); }
.track { grid-column: 1 / -1; height:.4em; border-radius:.2em; background:var(--track); overflow:hidden; }
.fill { height:100%; background:var(--bar); border-radius:.2em; }
.fill.warn { background:var(--warn); } .fill.out { background:var(--out); }
.empty { color:var(--muted); }
.foot { display:flex; flex-wrap:wrap; gap:.3rem 1.2rem; font-size:.8rem; color:var(--faint); }
.issues { color:var(--warn); }
/* Phones: one card per row at a fixed height, and the page scrolls. */
@media (max-width: 640px) {
  main { height:auto; min-height:100svh; }
  #cards { display:flex; flex-direction:column; }
  .card { height:auto; flex:none; container-type:normal; }
  .in { font-size:15px; gap:.9em; padding:1em 1.1em; }
  .bars { gap:.7em; }
  .top h1 { font-size:1.45rem; }
}
</style>
</head>
<body>
<main>
  <header class="top">
    <h1 id="verdict">Loading…</h1>
    <p class="sub" id="sub"></p>
    <p class="error" id="error" hidden>OpenUsage isn't answering on this Mac. Open the OpenUsage menu bar app, then this page refreshes by itself.</p>
  </header>
  <div id="cards"></div>
  <div class="foot"><span id="footer"></span><span class="issues" id="issues" hidden></span></div>
</main>
<script>
const REFRESH_MS = 30000;

function left(ms) {
  if (ms <= 0) return "now";
  const m = Math.round(ms / 60000), d = Math.floor(m / 1440), h = Math.floor((m % 1440) / 60), r = m % 60;
  return d ? d + "d " + h + "h" : h ? h + "h" + (r ? " " + r + "m" : "") : r + "m";
}
function until(iso) { return iso ? left(new Date(iso) - Date.now()) : null; }
function pct(r) { return r && typeof r.remaining === "number" ? Math.max(0, Math.min(100, Math.round(r.remaining))) : null; }
function label(id, p) {
  const raw = (p.displayName || id).replace(/'s Organization$/, "");
  const m = raw.match(/^Claude\s*[—:–-]\s*(.+)$/);
  return m ? { family: "Claude", detail: m[1] } : { family: raw, detail: p.plan || "" };
}
function el(tag, cls, text) { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
// Reset time for one bar: "resets in 2h 7m" inside a day, else "resets Thu 9 AM"; "back …" in red
// when that limit is used up; "not started" when a window has no clock running yet.
function resetText(res, value) {
  if (!res) return "";
  if (!res.resetsAt) return value != null && value >= 100 ? "not started" : "";
  const ms = new Date(res.resetsAt) - Date.now();
  return (value === 0 ? "back " : "resets ") +
    (ms <= 0 ? "now" : ms < 86400000 ? "in " + left(ms) : stamp(new Date(res.resetsAt).getTime()));
}

// Short weekday + time, minutes only when non-zero: "Tue 3 PM", "Tue 3:30 PM". More than six days
// out a weekday is ambiguous, so it becomes a date: "5 Nov".
function stamp(ms) {
  const d = new Date(ms), o = { weekday: "short", hour: "numeric" };
  if (ms - Date.now() > 6 * 86400000) return d.getDate() + " " + d.toLocaleDateString([], { month: "short" });
  if (d.getMinutes()) o.minute = "2-digit";
  return d.toLocaleString([], o);
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
    const first = (Array.isArray(exp) ? exp : []).map(x => new Date(x)).filter(d => !isNaN(d)).sort((a, b) => a - b)[0];
    out.push(passes + (passes === 1 ? " reset pass" : " reset passes") +
      (first ? " until " + first.getDate() + " " + first.toLocaleDateString([], { month: "short" }) : ""));
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
  let bars = [["Session", session], [longName, long], ["Fable", fable]].filter(([, res]) => res);
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
    note = latest ? "Back in " + until(latest) : "Out of room";
    backMs = latest ? new Date(latest).getTime() : null;
  } else if (soon) {
    const when = soon.fullMs - now < 86400000 ? "in " + left(soon.fullMs - now) : stamp(soon.fullMs);
    warn = true;
    note = "Runs out " + when;
    noteTitle = soon.name + " on pace to run out " + when + ", before it resets " + stamp(soon.resetMs);
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
function rank(x) { return x.out ? 2 : x.score < 10 ? 1 : 0; }
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

function clock(iso) { return new Date(iso).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }); }

// How a card reads: out (a limit at 0), warn (on pace to run out, or under 25% left), else ready.
function tone(x) { return x.out ? "out" : (x.warn || x.score < 25) ? "warn" : "ok"; }

function meter(value, name, res) {
  const box = el("div", "meter");
  const when = resetText(res, value);
  box.append(el("span", "lbl", name), el("span", "when" + (value === 0 ? " out" : ""), when),
    el("span", "pct" + (value === 0 ? " out" : ""), value == null ? "–" : value + "%"));
  const track = el("div", "track");
  if (value != null) {
    const fill = el("div", "fill" + (value <= 0 ? " out" : value < 25 ? " warn" : ""));
    fill.style.width = (value <= 0 ? 3 : value) + "%";
    track.appendChild(fill);
  }
  box.appendChild(track);
  return box;
}

// Headline: what is left before the reset and when that reset comes ("91% left · resets in 3d 20h"),
// then a status: Back in … / Runs out … / <limit> low / Use this one / Ready.
function card(x, isBest) {
  const t = tone(x);
  const box = el("div", "card" + (isBest ? " best" : "") + (x.p.stale ? " stale" : ""));
  const inner = el("div", "in");
  const who = el("div", "who");
  const kicker = [x.isClaude ? "Claude" : "", x.p.plan || ""].filter(Boolean).join(" · ");
  const krow = el("div", "krow");
  krow.appendChild(el("div", "kicker", kicker || " "));
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
  if (!x.out && x.resetMs) side.appendChild(el("div", "resetin", "resets in " + left(x.resetMs - Date.now())));
  const status = el("div", "status " + t);
  status.append(el("span", "dot"), x.out || x.warn ? x.note : isBest ? "Use this one" : x.score < 25 ? x.low + " low" : "Ready");
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

// Pick the column count that gives every card the most room: try each count, size the cells, and
// keep the one whose cards can hold the biggest text (cards want to be about as tall as wide).
function fit() {
  const grid = document.getElementById("cards"), n = grid.children.length;
  if (!n || matchMedia("(max-width: 640px)").matches) return;
  const gap = parseFloat(getComputedStyle(grid).columnGap) || 0;
  const W = grid.clientWidth, H = grid.clientHeight;
  let best = { cols: 1, rows: n, size: 0 };
  for (let cols = 1; cols <= n; cols++) {
    const rows = Math.ceil(n / cols);
    const w = (W - gap * (cols - 1)) / cols, h = (H - gap * (rows - 1)) / rows;
    const size = Math.min(w / 1.15, h);
    if (size > best.size + 0.5) best = { cols, rows, size };
  }
  grid.style.setProperty("--cols", best.cols);
  grid.style.setProperty("--rows", best.rows);
}
new ResizeObserver(fit).observe(document.documentElement);

function render(data) {
  const providers = data.providers || {};
  const rows = Object.entries(providers).map(([id, p]) => toRow(id, p)).filter(Boolean).sort(byUseFirst);
  const verdict = document.getElementById("verdict"), sub = document.getElementById("sub");
  verdict.textContent = ""; sub.textContent = "";
  const best = rows.find(x => !x.out);
  if (!rows.length) {
    verdict.textContent = "No accounts yet";
    sub.textContent = "Turn providers on in the OpenUsage menu bar app and they appear here.";
  } else if (best) {
    const when = best.resetMs ? ", resets in " + left(best.resetMs - Date.now()) : "";
    verdict.append("Use ", accountName(best), el("span", "dim", " · " + best.leftover + "% left" + when));
    const ready = rows.filter(x => !x.out).length;
    sub.textContent = ready + " of " + rows.length + " accounts ready · soonest reset first, because room left at a reset is lost";
  } else {
    const first = rows.map(x => x.backMs).filter(Boolean).sort((a, b) => a - b)[0];
    verdict.textContent = "Every account is out";
    sub.textContent = first ? "First one back in " + left(first - Date.now()) : "No reset time reported yet";
  }
  const grid = document.getElementById("cards");
  grid.textContent = "";
  for (const x of rows) grid.appendChild(card(x, x === best));
  fit();
  // Accounts whose last refresh failed: their card (if any) shows older numbers, so say which.
  const failed = (data.errors || []).map(e => {
    const p = providers[e.providerId];
    return (p && p.displayName || e.providerId) + (e.message ? " (" + e.message + ")" : "");
  });
  const issues = document.getElementById("issues");
  issues.hidden = !failed.length;
  issues.textContent = failed.length ? "Couldn't refresh: " + failed.join(" · ") : "";
  // The oldest numbers on screen, not the time of this request: a stalled account shows its real age.
  const oldest = rows.map(x => x.p.fetchedAt).filter(Boolean).sort()[0];
  document.getElementById("footer").textContent =
    (oldest ? "Data as of " + clock(oldest) : "No data yet") + " · refreshes every 30 seconds";
}

async function refresh() {
  try {
    const res = await fetch("/v1/limits", { cache: "no-store" });
    if (!res.ok) throw new Error(res.status);
    render(await res.json());
    document.getElementById("error").hidden = true;
  } catch (e) {
    document.getElementById("error").hidden = false;
  }
}
refresh();
setInterval(refresh, REFRESH_MS);
document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(); });
</script>
</body>
</html>
"""#
}
