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
<title>Seats · OpenUsage</title>
<style>
:root { --bg:#f6f6f4; --card:#fff; --text:#1d1d1b; --muted:#6b6b66; --line:#e6e5e0; --track:#ecebe6;
        --bar:#2f7de1; --warn:#c98a12; --out:#d64545; --ok:#2f9e5b; }
@media (prefers-color-scheme: dark) {
  :root { --bg:#161615; --card:#1f1f1d; --text:#ecebe6; --muted:#9a9993; --line:#2e2e2b; --track:#2e2e2b;
          --bar:#4b95f0; --warn:#e0a640; --out:#f06a6a; --ok:#4cc27e; }
}
* { box-sizing: border-box; }
/* Fills the browser window and scales with it: type grows from phone to big screen, the rows share
   the window's height, and under 760px each account becomes a stacked card with labelled bars. */
html { font-size: clamp(15px, 0.7vw + 0.7vh + 6px, 30px); }
body { margin:0; background:var(--bg); color:var(--text);
       font: 1rem/1.4 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; }
main { min-height:100vh; display:flex; flex-direction:column; padding: clamp(16px, 3vw, 56px); }
.best { color:var(--muted); margin: 0 0 .8em .25em; font-size:1.15em; overflow-wrap:anywhere; }
.best b { color:var(--text); font-weight:600; }
.card { flex:1; display:flex; flex-direction:column; background:var(--card); border:1px solid var(--line);
        border-radius:.9em; overflow:hidden; }
.row { flex:1 1 auto; display:grid; grid-template-columns: minmax(0,1.6fr) 1fr 1fr 1fr minmax(0,1fr);
       gap:1.2em; align-items:center; padding:.8em 1.2em; border-top:1px solid var(--line); }
.row:first-child { border-top:none; }
.head { flex:none; color:var(--muted); font-size:.8em; padding-top:.7em; padding-bottom:.7em; }
.name { white-space:nowrap; overflow:hidden; text-overflow:ellipsis; font-size:1.1em; }
.name small { color:var(--muted); margin-left:.4em; font-size:.85em; }
.acct { min-width:0; }
.extras { font-size:.85em; color:var(--muted); margin-top:.2em; }
.meter { display:flex; flex-wrap:wrap; align-items:center; gap:.25em .6em; }
.when { width:100%; font-size:.78em; color:var(--muted); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.when.out { color:var(--out); }
.track { flex:1; height:.5em; border-radius:.25em; background:var(--track); overflow:hidden; }
.fill { height:100%; background:var(--bar); }
.fill.warn { background:var(--warn); } .fill.out { background:var(--out); }
.pct { width:3.2em; text-align:right; color:var(--muted); font-variant-numeric: tabular-nums; }
.pct.out { color:var(--out); }
.note { text-align:right; color:var(--muted); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.note.out { color:var(--out); }
.note.warn { color:var(--warn); }
.note.ok { color:var(--ok); }
.stale { opacity:.55; }
footer { color:var(--muted); font-size:.85em; margin:.8em .3em 0; }
.error { color:var(--out); margin: 0 0 .8em .25em; }
.issues { color:var(--warn); font-size:.9em; margin: .8em .3em 0; }
.empty { color:var(--muted); padding:1em 1.2em; border-top:1px solid var(--line); }
@media (max-width: 760px) {
  .head { display:none; }
  .row { grid-template-columns: repeat(3, minmax(0,1fr)); grid-template-areas: "acct acct note" "s w f";
         gap:.6em 1em; padding:.9em 1em; }
  .acct { grid-area: acct; } .note { grid-area: note; }
  .meter { flex-wrap:wrap; gap:.2em .5em; }
  .meter::before { content: attr(data-label); width:100%; font-size:.75em; color:var(--muted); }
  .pct { width:auto; }
  .note { white-space:normal; }
}
</style>
</head>
<body>
<main>
  <p class="best" id="best"></p>
  <p class="error" id="error" hidden>OpenUsage isn't answering. Is the app running?</p>
  <div class="card" id="table">
    <div class="row head"><span>Account</span><span>Session</span><span>Weekly</span><span>Fable</span><span style="text-align:right">Status</span></div>
  </div>
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
  let note = "Ready", out = false, warn = false, noteTitle = "";
  const now = Date.now();
  const longName = long && long.windowSeconds > 8 * 86400 ? "Monthly" : "Weekly";
  const soon = [["Session", session], [longName, long], ["Fable", fable]]
    .map(([n, res]) => runOut(n, res, now)).filter(Boolean).sort((a, b) => a.fullMs - b.fullMs)[0];
  const blocked = [["Session", session, s], ["Weekly", long, w], ["Fable", fable, f]].filter(([, res, v]) => v === 0);
  if (blocked.length) {
    out = true;
    const latest = blocked.map(([, res]) => res && res.resetsAt).filter(Boolean).sort().pop();
    note = latest ? "Out · back in " + until(latest) : "Out of room";
  } else if (soon) {
    const when = soon.fullMs - now < 86400000 ? "in " + left(soon.fullMs - now) : stamp(soon.fullMs);
    warn = true;
    note = "Runs out " + when;
    noteTitle = soon.name + " on pace to run out " + (soon.fullMs - now < 86400000 ? when : stamp(soon.fullMs)) +
      ", before it resets " + stamp(soon.resetMs);
  }
  return { id, p, s, w, f, session, long, fable, score, longName, note, noteTitle, warn, out, extras: extras(r), isClaude: id.startsWith("claude") };
}

function clock(iso) { return new Date(iso).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }); }

function render(data) {
  const providers = data.providers || {};
  const rows = Object.entries(providers).map(([id, p]) => toRow(id, p)).filter(Boolean);
  const claude = rows.filter(x => x.isClaude).sort((a, b) => b.score - a.score);
  const others = rows.filter(x => !x.isClaude);
  const table = document.getElementById("table");
  table.querySelectorAll(".row:not(.head), .empty").forEach(n => n.remove());
  if (!rows.length) {
    table.appendChild(el("div", "empty", "No account has usage limits to show yet. Turn providers on in OpenUsage."));
  }
  for (const x of claude.concat(others)) {
    const row = el("div", "row" + (x.p.stale ? " stale" : ""));
    const name = label(x.id, x.p), acct = el("div", "acct"), cell = el("div", "name");
    cell.append(name.family, el("small", null, name.detail));
    cell.title = (x.p.displayName || x.id) + (x.p.plan ? " · " + x.p.plan : "");
    acct.appendChild(cell);
    if (x.extras.length) acct.appendChild(el("div", "extras", x.extras.join(" · ")));
    const note = el("div", "note" + (x.out ? " out" : x.warn ? " warn" : " ok"), x.note);
    if (x.noteTitle) note.title = x.noteTitle;
    row.append(acct, meter(x.s, "Session", x.session), meter(x.w, x.longName, x.long), meter(x.f, "Fable", x.fable), note);
    table.appendChild(row);
  }
  const best = claude.find(x => !x.out);
  const bestLine = document.getElementById("best");
  bestLine.textContent = "";
  if (best) {
    const n = label(best.id, best.p);
    bestLine.append("Most room now: ", el("b", null, n.family + " · " + n.detail));
  } else if (claude.length) {
    bestLine.textContent = "Every Claude account is out of room right now.";
  }
  const ready = rows.filter(x => !x.out).length;
  if (rows.length) bestLine.append((bestLine.textContent ? "  ·  " : "") + ready + " of " + rows.length + " accounts ready");
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
