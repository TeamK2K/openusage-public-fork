# Local HTTP API

OpenUsage exposes an HTTP API on the loopback interface so other local apps can consume the same usage data shown in the menu bar. It is read-only except for the accounts page's sign-in routes under `/v1/accounts`.

**Base URL:** `http://127.0.0.1:6736`

The server starts automatically with the app. If the port is already in use, the feature is silently disabled for that session.

## Routes

### `GET /`

A compact accounts page for people, not scripts. It reads `/v1/limits` from the same address and
refreshes itself every 30 seconds; it follows the Mac's light or dark appearance.

- **Top:** a bar with the title and **Add Account**, then a one-line answer ("Use <account> · N% left,
  resets in 3d 20h") and how many accounts are ready.
- **Cards:** one per account, all fitted on one screen with no scrolling (phones scroll); the page
  picks the biggest text at which no card overflows. Claude accounts go by their email. Each card says
  what is left before its weekly (or monthly) reset and how long until it, its plan and any reset passes
  or extra credit, a status badge (Use this one, Ready, <limit> low, Runs out in …, Back in …; green,
  amber or red), and its limits as ten-cell battery bars (weekly or monthly first, then session and
  Fable), each with its reset time. A bar changes colour as it runs low (under 75% left, then under
  40%).
- **Order:** soonest reset first, because room left at a reset is lost; accounts under 10% come next
  and accounts at a limit last, soonest back first. The first card is the account to use and is
  outlined. An **In Use** badge marks every account whose usage was seen going up in the last 15 minutes
  (the provider's `usageRoseAt`), so you can see when a session runs on a different account.
- **Signed out:** an account with no data at all (a Claude account no login holds) is a card with its
  message instead of bars, and counts as not ready.
- **Footer:** the age of the oldest numbers shown, and any account whose last refresh failed.

Every time on the page is relative, in one format: "in 45m", "in 2h 29m", "in 6d 2h", "in 13d" (minutes
are dropped a day or more out, hours ten days or more out); there are no clock times or dates.
`GET /seats` serves the same page. Settings → **Click Opens Web Page** makes the menu bar icon open it.

The page is one self-contained HTML file (no external assets) built from `web/accounts-page` with
`script/build_accounts_page.sh`; the built file is committed, so building the app needs no Node.

**Adding and signing in accounts.** A top bar carries the page title and an **Add Account** button.
Add Account → Claude or Codex makes the next free seat folder exactly as machine-config's `seat add`
does (`~/.claude-seatN` or `~/.codex-seatN`, owner-only, with an empty `.seat` marker; N is one past the
highest seat number either tool uses) and runs that tool's login with only that folder as its home
(`claude auth login` with `CLAUDE_CONFIG_DIR`, `codex login` with `CODEX_HOME`), which opens the
browser. While it waits a dialog shows **Waiting for sign-in…**, the sign-in link the tool printed,
and a **Paste Code** box: a code goes to the login, and the address of a sign-in page that didn't load
(Chrome can answer "HTTP 431" on the local return page when localhost cookies grow too big) is opened
by the app itself, without cookies, which finishes the same step. A signed-out Claude card has a
**Sign In** button that runs the same login in the seat folder it was last signed in at (made again if
it was removed); an account last signed in at the default folder or Claude Desktop signs in to a new
seat instead, so whatever account holds that place now is never replaced. One sign-in runs at a time;
it stops after 10 minutes, and Cancel (or closing the dialog) stops it. When it succeeds the app looks for accounts again and
the new card appears on the page without a restart; the menu bar panel shows it from the next launch.
A missing `claude`/`codex`, a login that fails, or a timeout shows the reason on the page and in the
log.

### `GET /v1/limits`

Returns a machine-facing envelope for all **enabled** providers. Providers and resources are keyed by
stable IDs; values are raw scalars with explicit units. This is the preferred route for new integrations
and the exact format printed by the `openusage` CLI.

### `GET /v1/limits/:id`

Returns the same envelope containing every provider the ID names. It works for disabled providers too.
Matching is plain string comparison: an exact provider ID names that provider, and a family ID
(`claude`, `codex`) names every account card of that family — with one account that's exactly the one
card. There is no aliasing or "pick the right account" logic; the same request always names the same
providers.

- **200 OK** — limits envelope with every matched provider that has data (an `errors` entry appears
  when a refresh failed; a matched provider with no data yet simply has no entry).
- **404 Not Found** — the ID names no known provider and no family.

### `GET /v1/usage`

Returns the legacy UI-oriented snapshots for all **enabled** providers, in your dashboard order. Existing
consumers remain supported while this route is deprecated; new consumers should use `/v1/limits`.

Both routes read the same rendered provider snapshots. When iCloud Sync is on, that means they both see
the same iCloud-combined usage as the dashboard; `/v1/usage` returns the old UI-oriented shape, while
`/v1/limits` projects the data into stable resource IDs and raw scalar values.

- **200 OK** — JSON array (may be empty `[]` if nothing has been fetched yet).

### `GET /v1/usage/:id`

Returns the latest snapshots for every provider the ID names (same matching as `/v1/limits/:id`).
Works for disabled providers too.

- **200 OK** — JSON array, one snapshot per matched provider that has one (`[]` when none do yet).
- **404 Not Found** — the ID names no known provider and no family.

> **Breaking change:** this route previously returned a single JSON object and `204` when the
> provider had no snapshot. It now always returns an array, so the shape stays identical whether an
> ID names one provider or a whole account family.

### Sign-in routes (`/v1/accounts/…`)

Used by the accounts page. Every answer is the sign-in status, with an `error` code when the request
was refused:

```jsonc
{
  "phase": "waiting",                 // idle, waiting, succeeded, failed
  "tool": "claude",
  "seat": "seat4",
  "folder": "~/.claude-seat4",
  "url": "https://claude.ai/oauth/authorize?…",   // once the login printed it
  "message": "Waiting for sign-in…",
  "startedAt": "2026-10-23T12:00:00.000Z",
  "signInProviderIds": ["claude@ab12cd34"]        // signed-out cards that get a Sign In button
}
```

| Route | Body | Answer |
| --- | --- | --- |
| `GET /v1/accounts/signin` | — | **200** the status |
| `POST /v1/accounts/add` | `{"tool":"claude"}` or `"codex"` | **202** started; **409** `sign_in_in_progress`; **500** `sign_in_failed` (missing CLI, folder or launch failure; `message` says which) |
| `POST /v1/accounts/signin` | `{"providerId":"claude@…"}` | as above, plus **404** `provider_not_found` for a card that isn't signed out |
| `POST /v1/accounts/signin/code` | `{"code":"…"}` | **202** passed on; **409** `no_sign_in` when nothing is waiting |
| `POST /v1/accounts/signin/cancel` | — | **200**; stops a running sign-in or clears a finished one |

A body that isn't a JSON object with the named string field is **400** `bad_request`; a body over 16 KB
is **413**. These routes have no auth or origin check, by the owner's call.

### Everything else

Methods other than `GET`/`OPTIONS` (and the `POST` sign-in routes above) return **405**; unknown routes return **404**. When the server is already handling its maximum of 16 concurrent connections, requests get **503** — back off and retry.

## Limits response shape

```jsonc
{
  "schema": "openusage.limits.v1",
  "generatedAt": "2026-07-13T01:40:00.000Z",
  "providers": {
    "codex": {
      "displayName": "Codex",
      "plan": "Pro 200",
      "fetchedAt": "2026-07-13T01:39:30.000Z",
      "expiresAt": "2026-07-13T01:44:30.000Z",
      "stale": false,
      "resources": {
        "session": {
          "kind": "consumption",
          "unit": "percent",
          "used": 42,
          "limit": 100,
          "remaining": 58,
          "utilization": 0.42,
          "resetsAt": "2026-07-13T06:00:00.000Z",
          "windowSeconds": 18000
        },
        "credits": {
          "kind": "balance",
          "unit": "credits",
          "available": 821
        }
      }
    }
  },
  "errors": []
}
```

`kind` is `consumption` (`used`) or `balance` (`available`). Bounded consumption also carries `limit`,
`remaining`, and a 0–1 `utilization`. Reset, window, expiry-list, and `estimated` fields appear only when
the provider supplies that meaning. A provider or resource with no current value is omitted rather than
invented as zero. `expiresAt` is always `fetchedAt` plus the same five-minute freshness interval used by
the app and CLI; `stale` says whether that instant has passed. `usageRoseAt` (HTTP API only) is the latest refresh at which one of the provider's consumption totals went up compared with its previous refresh, counted only between refreshes at most 15 minutes apart so usage made while the app was closed never shows; it is omitted until the app has seen a rise since launch. Refresh failures appear in `errors` as
`{"providerId":"…","message":"…","displayName":"…"}` (`displayName` is the card's name, so a card with no
data can still be listed) while a last-good provider snapshot remains available.
For bounded progress resources, `unit` follows the provider's live metric format. For example, Cursor
`totalUsage` is `percent` on percentage-based plans, `requests` on request-based Enterprise plans, and
`usd` when Cursor reports a dollar pool. Copilot `premiumCredits` is `percent` on paid plans and a
`credits` count on org-managed seats that only report personal `credits_used`. OpenCode `session`,
`weekly`, and `monthly` are `percent`. An untouched OpenCode `session` omits `resetsAt`; the field appears
with the anchored reset instant after the first model call starts the rolling window, even while `used`
is still 0 because OpenCode reports whole percentages.

### Public resources

| Provider | Resource keys |
| --- | --- |
| Claude | `session`, `weekly`, `sonnet`, `fable`, `extraUsage`, `rateLimitResets` |
| Codex | `session`, `weekly`, `spark`, `sparkWeekly`, `credits`, `creditValue`, `rateLimitResets` |
| Cursor | `totalUsage`, `grokBot`, `autoUsage`, `apiUsage`, `onDemand`, `requests`, `credits` |
| Antigravity | `geminiSession`, `geminiWeekly`, `argonWeekly`, `nonGeminiSession`, `nonGeminiWeekly` |
| Copilot | `premiumCredits`, `extraUsage`, `orgCredits`, `orgSpend`, `chat`, `completions` |
| Devin | `daily`, `weekly`, `extraUsageBalance` |
| Grok | `weekly` |
| Ollama | `session`, `weekly`, `monthly` |
| OpenCode | `session`, `weekly`, `monthly` |
| OpenRouter | `credits`, `balance`, `keyLimit` |
| Z.ai | `session`, `weekly`, `webSearches` |

Charts, colors, subtitles, formatted badges, layout state, and historical spend periods stay out of this
contract. Codex's combined Credits UI row becomes two scalar resources: `credits` and `creditValue`.
Antigravity's `argonWeekly` reports the separate Gemini 4 Argon weekly quota when the account exposes
it. It is omitted when unavailable, including on older endpoints and accounts without that quota.

## Legacy usage response shape

```jsonc
{
  "providerId": "claude",
  "displayName": "Claude",
  "plan": "Team 5x",
  "lines": [
    {
      "type": "progress",
      "label": "Session",
      "used": 42.0,
      "limit": 100.0,
      "format": { "kind": "percent" },          // or "dollars", or "count" (+ "suffix")
      "resetsAt": "2026-03-26T13:00:00.161Z",   // optional
      "periodDurationMs": 18000000,             // optional
      "color": null
    },
    {
      "type": "text",
      "label": "Today",
      "value": "$5.17 · 9.2M tokens",
      "color": null,
      "subtitle": null
    },
    {
      "type": "badge",
      "label": "Pay as you go",
      "text": "2500 cap",
      "color": "#22c55e",
      "subtitle": null
    },
    {
      "type": "barChart",
      "label": "Usage Trend",
      "points": [
        { "label": "Mar 25", "value": 1200000.0, "valueLabel": "1.2M tokens" },
        { "label": "Mar 26", "value": 2400000.0, "valueLabel": "2.4M tokens" }
      ],
      "note": "Estimated from local Claude logs at API rates.",
      "color": null
    }
  ],
  "fetchedAt": "2026-03-26T11:16:29.000Z"
}
```

Line types are `progress`, `text`, `badge`, and `barChart`. A `barChart` line carries a `points` array — one `{ label, value, valueLabel? }` per day, oldest first — plus an optional `note`; `value` is the day's token count, `valueLabel` its pre-formatted readout, and `label` a localized month/day (e.g. "Mar 25"). `fetchedAt` is when the snapshot was last fetched successfully (ISO 8601).

The in-app model breakdown shown when hovering spend rows is not included in this API yet. Spend rows continue to serialize as the same `text` lines so existing local integrations keep their current shape.

## Errors

```json
{ "error": "provider_not_found" }
```

Codes: `provider_not_found`, `not_found`, `method_not_allowed`, `server_busy`, `bad_request`,
`request_body_too_large`, `request_header_too_large`, and for the sign-in routes `sign_in_in_progress`,
`no_sign_in`, `sign_in_failed`.

## CORS and privacy

All responses include permissive CORS headers (`Access-Control-Allow-Origin: *`, methods `GET, OPTIONS`). `OPTIONS` requests return **204** for preflight.

The server only listens on the loopback interface (`127.0.0.1`), so it is not reachable from other machines on your network. Because the CORS header is permissive, though, a web page open in your browser can read your usage snapshots from this API while the app is running. The data exposed is the same usage numbers shown in the menu bar — no credentials or tokens are ever served. This matches the original app's behavior so existing integrations keep working.

The sign-in routes are not in the CORS methods, so another site's script can't send them JSON or read
their answers, but nothing else checks who is asking: any program on this Mac, or a web page sending a
plain form post, can start a sign-in or make an empty seat folder. A sign-in only finishes in your own
browser, and no credential is ever served.

## Caching behavior

The API serves whatever the app is showing: only successful fetches replace data, so a failed refresh never blanks the API — you keep getting the last good snapshot. See [Refreshing & caching](refreshing.md).
