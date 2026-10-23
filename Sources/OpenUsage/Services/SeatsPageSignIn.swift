import Foundation

/// The accounts page's Add Account and Sign In script (appended to `SeatsPage`). The app does the work
/// (`/v1/accounts/…`, see `AccountsAPI`): it makes the seat folder and runs the login; this follows the
/// sign-in in a panel above the cards: "Waiting for sign-in…", the sign-in link, a Paste Code box, and
/// how it ended. It also starts the page's refresh loop, once both scripts are defined.
enum SeatsPageSignIn {
    static let source = #"""
<script>
let signIn = { phase: "idle", signInProviderIds: [] };
let signInPoll = null;
const SIGN_IN_POLL_MS = 1500;
const TOOL_NAMES = { claude: "Claude", codex: "Codex" };

async function loadSignIn() {
  try {
    const res = await fetch("/v1/accounts/signin", { cache: "no-store" });
    if (res.ok) showSignIn(await res.json());
  } catch (e) { /* the limits fetch shows the not-answering banner */ }
}

async function postSignIn(path, body) {
  let data;
  try {
    const res = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body || {}) });
    data = await res.json();
  } catch (e) {
    data = Object.assign({}, signIn, { error: "unreachable", message: "OpenUsage isn't answering. Open the OpenUsage menu bar app, then try again." });
  }
  showSignIn(data);
  return data;
}

// A Sign In button for a signed-out card the app can sign back in.
function signInRow(id) {
  if (!(signIn.signInProviderIds || []).includes(id)) return null;
  const row = el("div", "signrow"), button = el("button", "btn primary", "Sign In");
  button.type = "button";
  button.disabled = signIn.phase === "waiting";
  button.onclick = () => postSignIn("/v1/accounts/signin", { providerId: id });
  row.appendChild(button);
  return row;
}

function showSignIn(s) {
  const before = signIn.phase, beforeIDs = (signIn.signInProviderIds || []).join(",");
  signIn = s;
  const waiting = s.phase === "waiting";
  // A refused request during a sign-in (one already running) keeps that sign-in and adds a notice.
  const refusedWhileWaiting = waiting && s.error;
  const box = document.getElementById("signin");
  const shown = s.phase !== "idle" || !!s.message;
  const wasShown = !box.hidden;
  box.hidden = !shown;
  box.classList.toggle("failed", s.phase === "failed" || (s.phase === "idle" && !!s.error));
  const where = [TOOL_NAMES[s.tool] || "", s.folder || ""].filter(Boolean).join(" · ");
  document.getElementById("siTitle").textContent =
    waiting ? "Waiting for sign-in…" : s.phase === "succeeded" ? "Signed In" : s.phase === "failed" ? "Sign-in failed" : "";
  const detail = waiting
    ? (where ? where + ". " : "") + (refusedWhileWaiting || s.message === "Waiting for sign-in…" ? "Finish in the browser window that opened. If the page shows a code, or doesn't load, paste the code or the page's address here." : s.message || "")
    : [where, s.message].filter(Boolean).join(". ");
  document.getElementById("siDetail").textContent = detail;
  document.getElementById("siNotice").textContent = refusedWhileWaiting ? s.message || "" : "";
  const link = document.getElementById("siLink");
  link.hidden = !(waiting && s.url);
  if (s.url) link.href = s.url;
  document.getElementById("siForm").hidden = !waiting;
  document.getElementById("siCancel").hidden = !waiting;
  document.getElementById("siClose").hidden = waiting || !shown;
  document.getElementById("addBtn").disabled = waiting;
  for (const b of document.querySelectorAll(".signrow .btn")) b.disabled = waiting;
  if (waiting && !signInPoll) signInPoll = setInterval(loadSignIn, SIGN_IN_POLL_MS);
  if (!waiting && signInPoll) { clearInterval(signInPoll); signInPoll = null; }
  // A sign-in that ended (the new card), or Sign In buttons that changed: redraw the cards.
  const ended = before !== s.phase && before !== "idle";
  if (ended || beforeIDs !== (s.signInProviderIds || []).join(",")) refresh();
  else if (wasShown !== shown) fit();
}

const addBtn = document.getElementById("addBtn"), addMenu = document.getElementById("addMenu");
function setMenu(open) { addMenu.hidden = !open; addBtn.setAttribute("aria-expanded", String(open)); }
addBtn.addEventListener("click", e => { e.stopPropagation(); setMenu(addMenu.hidden); });
document.addEventListener("click", () => setMenu(false));
for (const option of addMenu.querySelectorAll("[data-tool]")) {
  option.addEventListener("click", e => {
    e.stopPropagation();
    setMenu(false);
    postSignIn("/v1/accounts/add", { tool: option.dataset.tool });
  });
}
document.getElementById("siForm").addEventListener("submit", async e => {
  e.preventDefault();
  const input = document.getElementById("siCode");
  const data = await postSignIn("/v1/accounts/signin/code", { code: input.value });
  if (!data.error) input.value = "";
});
document.getElementById("siCancel").addEventListener("click", () => postSignIn("/v1/accounts/signin/cancel"));
document.getElementById("siClose").addEventListener("click", () => postSignIn("/v1/accounts/signin/cancel"));

refresh();
setInterval(refresh, REFRESH_MS);
document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(); });
</script>
</body>
</html>
"""#
}
