import { left, when } from '@/lib/time'

// The `/v1/limits` envelope (docs/local-http-api.md § Limits response shape), only the fields the page reads.
export type Resource = {
  kind?: string
  unit?: string
  used?: number
  limit?: number
  remaining?: number
  available?: number
  resetsAt?: string
  windowSeconds?: number
  expiresAt?: string[] | string
}

export type Provider = {
  displayName?: string
  plan?: string
  fetchedAt?: string
  stale?: boolean
  usageRoseAt?: string
  resources?: Record<string, Resource | undefined>
}

export type LimitsError = { providerId: string; message?: string; displayName?: string }

export type Limits = { providers?: Record<string, Provider>; errors?: LimitsError[] }

/** One limit: its percent left (null when the provider gives none) and whether it is on pace to run
 *  out before it resets. */
export type Bar = { name: string; res: Resource; value: number | null; runsOut: boolean }

export type Tone = 'ok' | 'warn' | 'out'

/** One card: an account with data, or (`down`) one the app remembers but cannot read (signed out). */
export type Row = {
  id: string
  p: Provider
  bars: Bar[]
  score: number
  leftover: number
  resetMs: number | null
  low: string
  backMs: number | null
  note: string
  noteTitle: string
  warn: boolean
  out: boolean
  extras: string[]
  isClaude: boolean
  down: boolean
  message: string
}

const ms = (iso: string) => new Date(iso).getTime()

function pct(r: Resource): number | null {
  return typeof r.remaining === 'number' ? Math.max(0, Math.min(100, Math.round(r.remaining))) : null
}

function label(id: string, p: Provider): { family: string; detail: string } {
  const raw = (p.displayName || id).replace(/'s Organization$/, '')
  const m = raw.match(/^Claude\s*[—:–-]\s*(.+)$/)
  return m?.[1] ? { family: 'Claude', detail: m[1] } : { family: raw, detail: p.plan || '' }
}

/** Reset time for one bar: "resets in 2h 7m"; "back in …" when that limit is used up; "not started"
 *  when a window has no clock running yet. */
export function resetText(res: Resource, value: number | null, now: number): string {
  if (!res.resetsAt) return value != null && value >= 100 ? 'not started' : ''
  return (value === 0 ? 'back ' : 'resets ') + when(ms(res.resetsAt), now)
}

/** When a window is on pace to hit 100% before it resets, else null. Needs a tenth of the window
 *  elapsed so an early spike does not raise a false alarm. */
function runOut(name: string, res: Resource, now: number) {
  if (!res.resetsAt || !(res.windowSeconds! > 0) || !(res.used! > 0)) return null
  const resetMs = ms(res.resetsAt)
  const windowSeconds = res.windowSeconds!
  const used = res.used!
  const elapsed = windowSeconds - (resetMs - now) / 1000
  if (!(elapsed / windowSeconds >= 0.1)) return null
  const fullMs = now + (Math.max(0, 100 - used) * elapsed / used) * 1000
  return fullMs < resetMs ? { name, fullMs, resetMs } : null
}

const money = (n: number) => '$' + Math.round(n).toLocaleString()
const amount = (res: Resource | undefined) => (res && typeof res.available === 'number' ? res.available : 0)

/** The small line under an account: reset passes and extra credit, each hidden at zero. */
export function extras(r: Record<string, Resource | undefined>, now: number): string[] {
  const out: string[] = []
  const passes = amount(r.rateLimitResets)
  if (passes > 0) {
    const exp = r.rateLimitResets?.expiresAt
    const first = (Array.isArray(exp) ? exp : []).map(ms).filter(t => !isNaN(t)).sort((a, b) => a - b)[0]
    out.push(passes + (passes === 1 ? ' reset pass' : ' reset passes') +
      (first ? (passes === 1 ? ', expires ' : ', first expires ') + when(first, now) : ''))
  }
  for (const key of ['extraUsage', 'onDemand']) {
    const x = r[key]
    if (x && x.unit === 'usd' && x.limit! > 0 && x.remaining! > 0) out.push(`${money(x.remaining!)} of ${money(x.limit!)} extra left`)
  }
  const balance = r.extraUsageBalance
  if (balance && amount(balance) > 0 && balance.unit === 'usd') out.push(`${money(amount(balance))} extra`)
  const credits = amount(r.credits)
  const value = r.creditValue?.unit === 'usd' ? amount(r.creditValue) : 0
  if (credits > 0) out.push(credits.toLocaleString() + ' credits' + (value > 0 ? ` (~${money(value)})` : ''))
  else if (value > 0) out.push(`${money(value)} credit`)
  return out
}

const title = (key: string) => key.replace(/([A-Z])/g, ' $1').replace(/^./, c => c.toUpperCase())
const lowest = (bars: Bar[]) => bars.reduce((a, b) => ((b.value ?? 100) < (a.value ?? 100) ? b : a))

export function toRow(id: string, p: Provider, now: number): Row | null {
  const r = p.resources || {}
  const session = r.session
  const long = r.weekly || r.totalUsage
  const fable = r.fable
  const longName = long && long.windowSeconds! > 8 * 86400 ? 'Monthly' : 'Weekly'
  // The week (or month) leads: it is the limit whose leftover a reset throws away.
  const candidates: [string, Resource | undefined][] = [[longName, long], ['Session', session], ['Fable', fable]]
  let named: { name: string; res: Resource }[] = candidates
    .filter((entry): entry is [string, Resource] => !!entry[1])
    .map(([name, res]) => ({ name, res }))
  // An account with other limits only (Copilot's chat and completions): show each percent limit.
  if (!session && !long) {
    named = Object.entries(r)
      .filter((entry): entry is [string, Resource] => !!entry[1] && entry[1].unit === 'percent' && typeof entry[1].remaining === 'number')
      .map(([key, res]) => ({ name: title(key), res }))
  }
  if (!named.length) return null
  const bars: Bar[] = named.map(b => ({ ...b, value: pct(b.res), runsOut: runOut(b.name, b.res, now) != null }))
  const score = Math.min(...bars.map(b => b.value ?? 100))
  let note = 'Ready'
  let noteTitle = ''
  let out = false
  let warn = false
  let backMs: number | null = null
  const soon = bars.map(b => runOut(b.name, b.res, now)).filter(x => x != null).sort((a, b) => a.fullMs - b.fullMs)[0]
  const blocked = bars.filter(b => b.value === 0)
  if (blocked.length) {
    out = true
    const latest = blocked.map(b => b.res.resetsAt).filter((x): x is string => !!x).sort().pop()
    note = latest ? 'Back ' + when(ms(latest), now) : 'Out of room'
    backMs = latest ? ms(latest) : null
  } else if (soon) {
    warn = true
    note = 'Runs out ' + when(soon.fullMs, now)
    noteTitle = `${soon.name} on pace to run out ${when(soon.fullMs, now)}, before it resets ${when(soon.resetMs, now)}`
  }
  // The room a reset throws away: the tightest limit other than the 5-hour session (the week's or
  // the month's), and when it resets. The card's headline and the use-first order read these.
  const longBars = bars.filter(b => b.name !== 'Session')
  const tight = lowest(longBars.length ? longBars : bars)
  return {
    id, p, bars, score, note, noteTitle, warn, out, backMs,
    leftover: tight.value ?? 100,
    resetMs: tight.res.resetsAt ? ms(tight.res.resetsAt) : null,
    low: lowest(bars).name,
    extras: extras(r, now),
    isClaude: id.startsWith('claude'),
    down: false,
    message: ''
  }
}

/** An account with an error and no data at all (signed out): a card of its own, with the message. */
export function downRow(e: LimitsError): Row {
  return {
    id: e.providerId, p: { displayName: e.displayName || e.providerId, plan: '' }, down: true,
    message: e.message || "Couldn't refresh", bars: [], out: false, warn: false, score: 0, leftover: 0,
    resetMs: null, backMs: null, extras: [], note: '', noteTitle: '', low: '', isClaude: e.providerId.startsWith('claude')
  }
}

// Use-first order: the account whose room resets soonest goes first, because room left at a reset
// is lost. Accounts under 10% come after the rest, and accounts at a limit last, soonest back first.
const rank = (x: Row) => (x.down ? 3 : x.out ? 2 : x.score < 10 ? 1 : 0)
export function byUseFirst(a: Row, b: Row): number {
  const at = a.out ? a.backMs : a.resetMs
  const bt = b.out ? b.backMs : b.resetMs
  return rank(a) - rank(b) || (at ?? Infinity) - (bt ?? Infinity) || b.leftover - a.leftover
}

// In use: the app saw this account's usage go up within the last 15 minutes (about three refreshes),
// so a session is running on it now — whichever account the page recommends.
const IN_USE_MS = 15 * 60_000
export const inUse = (p: Provider, now: number) => !!p.usageRoseAt && now - ms(p.usageRoseAt) <= IN_USE_MS

/** An account goes by its email (Claude) or, where the app has no email, its product name. */
export function accountName(x: Row): string {
  const n = label(x.id, x.p)
  return x.isClaude ? n.detail : n.family
}

/** How one limit's battery reads: out at 0 or on pace to run out before it resets, warn under 25%
 *  left, else ok — lots of room stays green. */
export const barTone = (b: Bar): Tone => (b.value === 0 || b.runsOut ? 'out' : b.value != null && b.value < 25 ? 'warn' : 'ok')

/** How a card reads: out (a limit at 0), warn (on pace to run out, or under 25% left), else ready. */
export const tone = (x: Row): Tone => (x.out ? 'out' : x.warn || x.score < 25 ? 'warn' : 'ok')

/** The card's status: Back in … / Runs out in … / Use this one / <limit> low / Ready. */
export function status(x: Row, isBest: boolean): string {
  if (x.out || x.warn) return x.note
  return isBest ? 'Use this one' : x.score < 25 ? `${x.low} low` : 'Ready'
}

export type Page = {
  rows: Row[]
  best: Row | undefined
  verdict: { lead: string; dim: string }
  sub: string
  issues: string
  footer: string
}

/** Everything the page shows for one `/v1/limits` answer. */
export function buildPage(data: Limits, now: number): Page {
  const providers = data.providers || {}
  const errors = data.errors || []
  const rows = Object.entries(providers).map(([id, p]) => toRow(id, p, now)).filter((x): x is Row => x != null)
    .concat(errors.filter(e => !providers[e.providerId]).map(downRow)).sort(byUseFirst)
  const live = rows.filter(x => !x.down)
  const best = live.find(x => !x.out)
  let verdict = { lead: '', dim: '' }
  let sub = ''
  if (!rows.length) {
    verdict = { lead: 'No accounts yet', dim: '' }
    sub = 'Add an account above, or turn providers on in the OpenUsage menu bar app.'
  } else if (best) {
    verdict = { lead: `Use ${accountName(best)}`, dim: ` · ${best.leftover}% left${best.resetMs ? ', resets ' + when(best.resetMs, now) : ''}` }
    const ready = live.filter(x => !x.out).length
    sub = `${ready} of ${rows.length} accounts ready · soonest reset first, because room left at a reset is lost`
  } else if (live.length) {
    const first = live.map(x => x.backMs).filter((x): x is number => x != null).sort((a, b) => a - b)[0]
    verdict = { lead: 'Every account is out', dim: '' }
    sub = first ? 'First one back ' + when(first, now) : 'No reset time reported yet'
  } else {
    verdict = { lead: 'No account is signed in', dim: '' }
    sub = 'Sign in to an account, then this page refreshes by itself.'
  }
  // Accounts whose last refresh failed: their card shows older numbers, so say which. A signed-out
  // account is a card of its own that already says so.
  const failed = errors.filter(e => providers[e.providerId]).map(e => {
    const p = providers[e.providerId]
    return (p?.displayName || e.providerId) + (e.message ? ` (${e.message})` : '')
  })
  // The oldest numbers on screen, not the time of this request: a stalled account shows its real age.
  const oldest = rows.map(x => x.p.fetchedAt).filter((x): x is string => !!x).sort()[0]
  const age = oldest ? now - ms(oldest) : null
  const footer = (age == null ? 'No data yet' : 'Data from ' + (age < 60_000 ? 'just now' : left(age) + ' ago')) +
    ' · refreshes every 30 seconds'
  return { rows, best, verdict, sub, issues: failed.length ? "Couldn't refresh: " + failed.join(' · ') : '', footer }
}
