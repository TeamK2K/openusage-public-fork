// Every time on the page is relative, in one format: "in 45m", "in 2h 29m", "in 6d 2h", "in 13d".
// Minutes go once it is a day or more away, hours once it is ten days or more away. No clock times or
// dates, so a card's lines stay short enough never to wrap.

const MINUTE = 60_000
const HOUR = 3_600_000
const DAY = 86_400_000

/** A duration in the page's one format, without the "in": "2h 29m", "6d 2h", "now". */
export function left(ms: number): string {
  if (ms <= 0) return 'now'
  if (ms >= DAY) {
    const hours = Math.round(ms / HOUR)
    const d = Math.floor(hours / 24)
    const h = hours % 24
    return d >= 10 ? `${Math.round(ms / DAY)}d` : `${d}d${h ? ` ${h}h` : ''}`
  }
  const m = Math.max(1, Math.round(ms / MINUTE))
  const h = Math.floor(m / 60)
  const r = m % 60
  return h ? `${h}h${r ? ` ${r}m` : ''}` : `${r}m`
}

/** How long until an instant: "in 2h 29m", or "now" once it has passed. */
export function when(ms: number, now: number = Date.now()): string {
  const diff = ms - now
  return diff <= 0 ? 'now' : `in ${left(diff)}`
}
