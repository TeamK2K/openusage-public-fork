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
        --bar:#2f7de1; --warn:#c98a12; --out:#d64545; }
@media (prefers-color-scheme: dark) {
  :root { --bg:#161615; --card:#1f1f1d; --text:#ecebe6; --muted:#9a9993; --line:#2e2e2b; --track:#2e2e2b;
          --bar:#4b95f0; --warn:#e0a640; --out:#f06a6a; }
}
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--text);
       font: 14px/1.4 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; }
main { max-width: 760px; margin: 40px auto; padding: 0 16px; }
.best { color:var(--muted); margin: 0 0 12px 4px; }
.best b { color:var(--text); font-weight:600; }
.card { background:var(--card); border:1px solid var(--line); border-radius:12px; overflow:hidden; }
.row { display:grid; grid-template-columns: minmax(0,1.6fr) 1fr 1fr minmax(0,1fr); gap:16px;
       align-items:center; padding:10px 16px; border-top:1px solid var(--line); }
.row:first-child { border-top:none; }
.head { color:var(--muted); font-size:12px; padding-top:8px; padding-bottom:8px; }
.name { white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.name small { color:var(--muted); margin-left:6px; }
.meter { display:flex; align-items:center; gap:8px; }
.track { flex:1; height:6px; border-radius:3px; background:var(--track); overflow:hidden; }
.fill { height:100%; background:var(--bar); }
.fill.warn { background:var(--warn); } .fill.out { background:var(--out); }
.pct { width:40px; text-align:right; color:var(--muted); font-variant-numeric: tabular-nums; }
.pct.out { color:var(--out); }
.note { text-align:right; color:var(--muted); font-size:13px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.note.out { color:var(--out); }
.stale { opacity:.55; }
footer { color:var(--muted); font-size:12px; margin:10px 4px; }
.error { color:var(--out); margin: 0 0 12px 4px; }
.issues { color:var(--warn); font-size:13px; margin: 10px 4px 0; }
.empty { color:var(--muted); padding:14px 16px; border-top:1px solid var(--line); }
</style>
</head>
<body>
<main>
  <p class="best" id="best"></p>
  <p class="error" id="error" hidden>OpenUsage isn't answering. Is the app running?</p>
  <div class="card" id="table">
    <div class="row head"><span>Account</span><span>Session</span><span>Weekly</span><span style="text-align:right">Next</span></div>
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
function meter(value) {
  const box = el("div", "meter"), track = el("div", "track");
  if (value != null) {
    const fill = el("div", "fill" + (value <= 0 ? " out" : value < 25 ? " warn" : ""));
    fill.style.width = (value <= 0 ? 3 : value) + "%";
    track.appendChild(fill);
  }
  box.append(track, el("span", "pct" + (value === 0 ? " out" : ""), value == null ? "–" : value + "%"));
  return box;
}

function toRow(id, p) {
  const r = p.resources || {};
  const session = r.session, long = r.weekly || r.totalUsage, fable = r.fable;
  if (!session && !long) return null;
  const s = pct(session), w = pct(long), f = pct(fable);
  const score = Math.min(s ?? 100, w ?? 100, f ?? 100);
  let note = "", out = false;
  const blocked = [["Session", session, s], ["Weekly", long, w], ["Fable", fable, f]].filter(([, res, v]) => v === 0);
  if (blocked.length) {
    out = true;
    const latest = blocked.map(([, res]) => res && res.resetsAt).filter(Boolean).sort().pop();
    note = latest ? "back in " + until(latest) : "limit reached";
  } else if (session && session.resetsAt) {
    note = "resets " + until(session.resetsAt);
  } else if (long && long.resetsAt) {
    note = (long.windowSeconds > 8 * 86400 ? "month " : "week ") + until(long.resetsAt);
  }
  return { id, p, s, w, score, note, out, isClaude: id.startsWith("claude") };
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
    const name = label(x.id, x.p), cell = el("div", "name");
    cell.append(name.family, el("small", null, name.detail));
    cell.title = (x.p.displayName || x.id) + (x.p.plan ? " · " + x.p.plan : "");
    row.append(cell, meter(x.s), meter(x.w), el("div", "note" + (x.out ? " out" : ""), x.note));
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
