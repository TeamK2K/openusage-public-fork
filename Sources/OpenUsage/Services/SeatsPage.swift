import Foundation

/// The concise "which account has room" page the local server serves at `/`. One row per account
/// with a session and a weekly (or monthly) bar, accounts out of room flagged in red, and the Claude
/// account with the most room called out on top. It reads `/v1/limits` from the same origin and
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
:root { --bg:#f7f7f5; --text:#1c1c1a; --muted:#6e6d68; --faint:#9c9b95; --line:#e4e3de; --track:#e9e8e3;
        --bar:#2f7de1; --warn:#b97c0c; --out:#d13f3f; --ok:#23915a; }
@media (prefers-color-scheme: dark) {
  :root { --bg:#141413; --text:#edece6; --muted:#a3a29b; --faint:#6f6e69; --line:#2a2a27; --track:#2c2c29;
          --bar:#4d96f2; --warn:#e3a43c; --out:#f06868; --ok:#52c886; }
}
* { box-sizing: border-box; }
/* Fills the window and scales with it: type grows from phone to big screen. */
html { font-size: clamp(15px, 0.5vw + 0.5vh + 6px, 26px); }
body { margin:0; background:var(--bg); color:var(--text);
       font: 1rem/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; }
main { min-height:100svh; padding: clamp(20px, 4vw, 72px) clamp(16px, 4vw, 72px) clamp(16px, 2.5vw, 40px);
       display:flex; flex-direction:column; gap: 2.2em; }
.top .kicker { margin:0 0 .3em; color:var(--muted); font-size:.85em; letter-spacing:.04em; text-transform:uppercase; }
.top h1 { margin:0; font-size:2.3em; line-height:1.15; font-weight:650; letter-spacing:-.01em; overflow-wrap:anywhere; }
.top h1 .dim { color:var(--muted); font-weight:500; }
.top .sub { margin:.45em 0 0; color:var(--muted); font-size:1.1em; }
.error { margin:.6em 0 0; color:var(--out); }
section + section { margin-top:2.2em; }
section h2 { margin:0 0 .5em; font-size:.85em; font-weight:600; color:var(--muted); letter-spacing:.04em; text-transform:uppercase;
             display:flex; gap:.6em; align-items:baseline; }
section h2 .count { font-weight:500; text-transform:none; letter-spacing:0; color:var(--faint); }
.grid { display:grid; grid-template-columns: minmax(0,1.6fr) 5.5em repeat(var(--bars), minmax(0,1fr)) minmax(0,1fr);
        column-gap:1.6em; align-items:center; }
.cols { color:var(--faint); font-size:.78em; padding:0 0 .5em; border-bottom:1px solid var(--line); }
.cols .r, .room, .status { text-align:right; }
.row { padding:1em 0; border-bottom:1px solid var(--line); }
.acct { min-width:0; display:flex; gap:.7em; align-items:flex-start; }
.dot { flex:none; width:.6em; height:.6em; border-radius:50%; margin-top:.5em; background:var(--ok); }
.dot.warn { background:var(--warn); } .dot.out { background:var(--out); }
.who { min-width:0; }
.name { font-size:1.12em; font-weight:600; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.name small { font-weight:400; color:var(--muted); margin-left:.4em; font-size:.85em; }
.extras { color:var(--muted); font-size:.82em; margin-top:.15em; }
.room { font-size:1.7em; font-weight:650; font-variant-numeric: tabular-nums; line-height:1; }
.room.warn { color:var(--warn); } .room.out { color:var(--out); }
.room small { display:block; font-size:.42em; font-weight:500; color:var(--faint); margin-top:.35em; letter-spacing:.03em; }
.meter { display:grid; grid-template-columns: 1fr auto; column-gap:.6em; row-gap:.3em; align-items:center; }
.na { color:var(--faint); }
.track { height:.42em; border-radius:.21em; background:var(--track); overflow:hidden; }
.fill { height:100%; background:var(--bar); border-radius:.21em; }
.fill.warn { background:var(--warn); } .fill.out { background:var(--out); }
.pct { color:var(--muted); font-variant-numeric: tabular-nums; font-size:.9em; min-width:2.6em; text-align:right; }
.pct.out { color:var(--out); }
.when { grid-column: 1 / -1; font-size:.78em; color:var(--faint); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.when.out { color:var(--out); }
.status { color:var(--muted); font-size:.95em; }
.status.warn { color:var(--warn); } .status.out { color:var(--out); }
.stale { opacity:.55; }
.empty { color:var(--muted); padding:1em 0; }
.issues { margin:0; color:var(--warn); font-size:.9em; }
footer { margin-top:auto; color:var(--faint); font-size:.82em; }
@media (max-width: 760px) {
  main { gap:1.6em; }
  .top h1 { font-size:1.7em; }
  .cols { display:none; }
  .grid { grid-template-columns: repeat(var(--bars), minmax(0,1fr)); grid-template-areas: "acct acct room" "bars bars bars" "status status status";
          row-gap:.7em; column-gap:1em; }
  .acct { grid-column: 1 / -2; } .room { grid-column: -2 / -1; }
  .meter::before { content: attr(data-label); grid-column: 1 / -1; font-size:.75em; color:var(--faint); }
  .status { grid-column: 1 / -1; text-align:left; }
  .status:empty { display:none; }
}
</style>
</head>
<body>
<main>
  <header class="top">
    <p class="kicker">AI accounts</p>
    <h1 id="verdict">Loading…</h1>
    <p class="sub" id="sub"></p>
    <p class="error" id="error" hidden>OpenUsage isn't answering on this Mac. Open the OpenUsage menu bar app, then this page refreshes by itself.</p>
  </header>
  <div id="sections"></div>
  <p class="issues" id="issues" hidden></p>
  <footer id="footer"></footer>
</main>
<script>
const REFRESH_MS = 30000;

function left(ms) {
  if (ms <= 0) return "now";
  const m = Math.round(ms / 60000), d = Math.floor(m / 1440), h = Math.floor((m % 1440) / 60), r = m % 60;
  return d ? d + "d " + h + "h" : h ? h + "h " + r + "m" : r + "m";
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
  return (value === 0 ? "back " : "resets ") + (ms < 86400000 ? "in " + left(ms) : stamp(new Date(res.resetsAt).getTime()));
}
function meter(value, label, res) {
  if (value == null && !res) return el("div", "na", "—");
  const box = el("div", "meter"), track = el("div", "track");
  box.dataset.label = label;
  if (value != null) {
    const fill = el("div", "fill" + (value <= 0 ? " out" : value < 25 ? " warn" : ""));
    fill.style.width = (value <= 0 ? 3 : value) + "%";
    track.appendChild(fill);
  }
  box.append(track, el("span", "pct" + (value === 0 ? " out" : ""), value == null ? "–" : value + "%"));
  const when = resetText(res, value);
  if (when) box.appendChild(el("div", "when" + (value === 0 ? " out" : ""), when));
  return box;
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

function toRow(id, p) {
  const r = p.resources || {};
  const session = r.session, long = r.weekly || r.totalUsage, fable = r.fable;
  if (!session && !long) return null;
  const s = pct(session), w = pct(long), f = pct(fable);
  const score = Math.min(s ?? 100, w ?? 100, f ?? 100);
  let note = "Ready", out = false, warn = false, noteTitle = "", backMs = null;
  const now = Date.now();
  const longName = long && long.windowSeconds > 8 * 86400 ? "Monthly" : "Weekly";
  const soon = [["Session", session], [longName, long], ["Fable", fable]]
    .map(([n, res]) => runOut(n, res, now)).filter(Boolean).sort((a, b) => a.fullMs - b.fullMs)[0];
  const blocked = [["Session", session, s], ["Weekly", long, w], ["Fable", fable, f]].filter(([, res, v]) => v === 0);
  if (blocked.length) {
    out = true;
    const latest = blocked.map(([, res]) => res && res.resetsAt).filter(Boolean).sort().pop();
    note = latest ? "Back in " + until(latest) : "Out of room";
    backMs = latest ? new Date(latest).getTime() : null;
  } else if (soon) {
    const when = soon.fullMs - now < 86400000 ? "in " + left(soon.fullMs - now) : stamp(soon.fullMs);
    warn = true;
    note = "Runs out " + when;
    noteTitle = soon.name + " on pace to run out " + (soon.fullMs - now < 86400000 ? when : stamp(soon.fullMs)) +
      ", before it resets " + stamp(soon.resetMs);
  }
  return { id, p, s, w, f, session, long, fable, score, backMs, longName, note, noteTitle, warn, out, extras: extras(r), isClaude: id.startsWith("claude") };
}

function clock(iso) { return new Date(iso).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }); }

// How a row reads: out (a limit at 0), warn (on pace to run out, or under 25% left), else ready.
function tone(x) { return x.out ? "out" : (x.warn || x.score < 25) ? "warn" : "ok"; }
function statusText(x) { return x.out || x.warn ? x.note : ""; }

// Every section keeps the same five columns so Room and the bars line up down the whole page.
function section(title, count, rows, withFable) {
  const bars = 3;
  const box = el("section");
  const h = el("h2", null, title);
  if (count) h.appendChild(el("span", "count", count));
  box.appendChild(h);
  const cols = el("div", "grid cols");
  cols.style.setProperty("--bars", bars);
  const longs = [...new Set(rows.filter(x => x.long).map(x => x.longName))];
  cols.append(el("span", null, "Account"), el("span", "r", "Room"), el("span", null, "Session"),
    el("span", null, longs.length > 1 ? "Week / month" : longs[0] || "Weekly"));
  cols.appendChild(el("span", null, withFable ? "Fable" : ""));
  cols.appendChild(el("span", "r", "Status"));
  box.appendChild(cols);
  for (const x of rows) {
    const t = tone(x);
    const row = el("div", "grid row" + (x.p.stale ? " stale" : ""));
    row.style.setProperty("--bars", bars);
    const name = label(x.id, x.p), acct = el("div", "acct"), who = el("div", "who"), cell = el("div", "name");
    cell.append(name.family, el("small", null, name.detail));
    cell.title = (x.p.displayName || x.id) + (x.p.plan ? " · " + x.p.plan : "");
    who.appendChild(cell);
    if (x.extras.length) who.appendChild(el("div", "extras", x.extras.join(" · ")));
    acct.append(el("span", "dot " + t), who);
    const room = el("div", "room " + t, x.score + "%");
    room.appendChild(el("small", null, "ROOM"));
    row.append(acct, room, meter(x.s, "Session", x.session), meter(x.w, x.longName, x.long));
    row.appendChild(withFable ? meter(x.f, "Fable", x.fable) : el("div"));
    const status = el("div", "status " + t, statusText(x));
    if (x.noteTitle) status.title = x.noteTitle;
    row.appendChild(status);
    box.appendChild(row);
  }
  return box;
}

function render(data) {
  const providers = data.providers || {};
  const rows = Object.entries(providers).map(([id, p]) => toRow(id, p)).filter(Boolean)
    .sort((a, b) => (a.out - b.out) || (b.score - a.score));
  const claude = rows.filter(x => x.isClaude), others = rows.filter(x => !x.isClaude);
  const sections = document.getElementById("sections");
  sections.textContent = "";
  const verdict = document.getElementById("verdict"), sub = document.getElementById("sub");
  verdict.textContent = ""; sub.textContent = "";
  if (!rows.length) {
    verdict.textContent = "No accounts yet";
    sub.textContent = "Turn providers on in the OpenUsage menu bar app and they appear here.";
  } else {
    const pool = claude.length ? claude : rows;
    const best = pool.find(x => !x.out);
    if (best) {
      const n = label(best.id, best.p);
      verdict.append("Use ", n.detail || n.family, el("span", "dim", " · " + best.score + "% room"));
      const ready = pool.filter(x => !x.out).length;
      sub.textContent = [n.family + (best.p.plan ? " " + best.p.plan : ""), ready + " of " + pool.length + " ready",
        "room is an account's tightest limit"].join(" · ");
    } else {
      const first = pool.map(x => x.backMs).filter(Boolean).sort((a, b) => a - b)[0];
      verdict.textContent = "Every " + (claude.length ? "Claude " : "") + "account is out";
      sub.textContent = first ? "First one back in " + left(first - Date.now()) : "No reset time reported yet";
    }
  }
  if (claude.length) sections.appendChild(section("Claude", claude.filter(x => !x.out).length + " of " + claude.length + " ready", claude, true));
  if (others.length) sections.appendChild(section(claude.length ? "Other tools" : "Accounts", "", others, others.some(x => x.f != null)));
  // Accounts whose last refresh failed: their row (if any) shows older numbers, so say which.
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
