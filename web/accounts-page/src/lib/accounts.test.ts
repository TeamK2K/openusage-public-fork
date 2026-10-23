import { describe, expect, it } from 'vitest'

import { buildPage, extras, resetText, status, toRow, type Provider, type Resource } from '@/lib/accounts'

const now = Date.parse('2026-10-23T12:00:00.000Z')
const iso = (offsetMs: number) => new Date(now + offsetMs).toISOString()
const hour = 3_600_000
const day = 24 * hour

const pctRes = (remaining: number, resetsIn: number, windowSeconds = 7 * 86400): Resource => ({
  kind: 'consumption', unit: 'percent', used: 100 - remaining, limit: 100, remaining,
  resetsAt: iso(resetsIn), windowSeconds
})

const claude = (email: string, resources: Provider['resources'], extra: Partial<Provider> = {}): Provider => ({
  displayName: `Claude: ${email}`, plan: 'Max', fetchedAt: iso(-30_000), resources, ...extra
})

describe('cards', () => {
  it('lead with the weekly bar, then session and Fable', () => {
    const row = toRow('claude@a', claude('a@x.com', {
      session: pctRes(80, 2 * hour, 18000), weekly: pctRes(60, 3 * day), fable: pctRes(90, 3 * day)
    }), now)!
    expect(row.bars.map(b => b.name)).toEqual(['Weekly', 'Session', 'Fable'])
    expect(row.leftover).toBe(60)
  })

  it('name a window over eight days Monthly', () => {
    const row = toRow('opencode', { displayName: 'OpenCode', resources: { weekly: pctRes(50, 20 * day, 30 * 86400) } }, now)!
    expect(row.bars[0]!.name).toBe('Monthly')
  })

  it('show every percent limit for an account with neither session nor weekly', () => {
    const row = toRow('copilot', { displayName: 'Copilot', resources: {
      chat: { unit: 'percent', remaining: 70 }, completions: { unit: 'percent', remaining: 40 }, credits: { kind: 'balance', unit: 'credits', available: 3 }
    } }, now)!
    expect(row.bars.map(b => b.name)).toEqual(['Chat', 'Completions'])
  })

  it('say when a used-up limit comes back', () => {
    const row = toRow('claude@a', claude('a@x.com', { session: pctRes(0, 2 * hour, 18000), weekly: pctRes(40, 3 * day) }), now)!
    expect(row.out).toBe(true)
    expect(status(row, false)).toBe('Back in 2h')
    expect(resetText(row.bars[1]!.res, 0, now)).toBe('back in 2h')
  })

  it('warn when a limit is on pace to run out before it resets', () => {
    // 6 of 7 days left and already 50% used: full in about a day.
    const row = toRow('claude@a', claude('a@x.com', { weekly: pctRes(50, 6 * day) }), now)!
    expect(row.warn).toBe(true)
    expect(status(row, true)).toMatch(/^Runs out in /)
  })

  it('list reset passes and extra credit, hidden at zero', () => {
    expect(extras({
      rateLimitResets: { kind: 'balance', available: 2, expiresAt: [iso(3 * day), iso(day)] },
      extraUsage: { unit: 'usd', limit: 100, remaining: 40 }
    }, now)).toEqual(['2 reset passes, first expires in 1d', '$40 of $100 extra left'])
    expect(extras({ rateLimitResets: { kind: 'balance', available: 0 } }, now)).toEqual([])
  })
})

describe('the page', () => {
  it('runs soonest reset first and names the first ready account on top', () => {
    const page = buildPage({ providers: {
      'claude@late': claude('late@x.com', { weekly: pctRes(90, 5 * day) }),
      'claude@soon': claude('soon@x.com', { weekly: pctRes(70, 1 * day) }),
      'claude@out': claude('out@x.com', { weekly: pctRes(0, 2 * hour) })
    }, errors: [] }, now)
    expect(page.rows.map(r => r.id)).toEqual(['claude@soon', 'claude@late', 'claude@out'])
    expect(page.best?.id).toBe('claude@soon')
    expect(page.verdict).toEqual({ lead: 'Use soon@x.com', dim: ' · 70% left, resets in 1d' })
    expect(page.sub).toMatch(/^2 of 3 accounts ready/)
    expect(page.footer).toBe('Data from just now · refreshes every 30 seconds')
  })

  it('gives a signed-out account a card of its own, last, with its message', () => {
    const page = buildPage({ providers: { 'claude@a': claude('a@x.com', { weekly: pctRes(50, 2 * day) }) }, errors: [
      { providerId: 'claude@gone', displayName: 'Claude: gone@x.com', message: 'Signed Out. Last signed in at ~/.claude-seat1.' }
    ] }, now)
    const down = page.rows.at(-1)!
    expect(down.down).toBe(true)
    expect(down.message).toBe('Signed Out. Last signed in at ~/.claude-seat1.')
    expect(page.issues).toBe('')
  })

  it('names accounts whose last refresh failed but still have numbers', () => {
    const page = buildPage({ providers: { codex: { displayName: 'Codex', resources: { session: pctRes(50, hour, 18000) } } }, errors: [
      { providerId: 'codex', message: 'HTTP 500' }
    ] }, now)
    expect(page.rows).toHaveLength(1)
    expect(page.issues).toBe("Couldn't refresh: Codex (HTTP 500)")
  })

  it('says so when there are no accounts, or none signed in', () => {
    expect(buildPage({ providers: {}, errors: [] }, now).verdict.lead).toBe('No accounts yet')
    expect(buildPage({ providers: {}, errors: [{ providerId: 'claude@a', message: 'Signed Out.' }] }, now).verdict.lead)
      .toBe('No account is signed in')
  })
})
