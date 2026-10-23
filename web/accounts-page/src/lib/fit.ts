// Fit every card on one screen at the biggest text that leaves nothing cut off: for each column count,
// search the card text size at which no card, and nothing inside a card, clips or overflows, and keep
// the column count that allows the biggest one. Measured, not estimated, so it holds for any card mix.
// Below MIN_FS text gets too small to read: when nothing fits even there, the cards keep MIN_FS, take
// the height they need, and the page scrolls. Phones get one card per row and the page scrolls.
//
// The size is set as `--fit` on the card grid (a scale of the 16px base): `src/index.css` scales the
// grid's spacing and text tokens by it, so only the cards change size — the top bar, verdict, footer
// and dialog keep one size whatever the card count or theme.

const MIN_FS = 11
const MAX_FS = 26
const BASE_FS = 16
export const PHONE_QUERY = '(max-width: 639px)'

const clipped = (e: Element, vertical: boolean) =>
  e.scrollWidth > e.clientWidth + 1 || (vertical && e.scrollHeight > e.clientHeight + 1)

/** Whether any card, or anything inside one (truncated text, a chart row wider than its column),
 *  is cut off, or the page itself overflows the window. With `scrolling` the cards and the page may
 *  grow downwards; only being cut off sideways counts. */
export function overflowing(grid: HTMLElement, scrolling = false): boolean {
  for (const card of Array.from(grid.children)) {
    if (clipped(card, !scrolling)) return true
    for (const e of Array.from(card.querySelectorAll('*'))) {
      if (e.clientWidth === 0 && e.clientHeight === 0) continue // inline and SVG boxes report no size
      // Charts size themselves on React's next render, so mid-search they still carry the previous
      // layout's size; `index.css` gives each chart box size containment, so only text can be cut off.
      if (e.closest('[data-slot="chart"]')) continue
      if (clipped(e, true)) return true
    }
  }
  const page = document.documentElement
  return page.scrollWidth > window.innerWidth + 1 || (!scrolling && page.scrollHeight > window.innerHeight + 1)
}

export function fit(grid: HTMLElement | null): void {
  if (!grid) return
  const root = document.documentElement
  const n = grid.children.length
  if (!n || matchMedia(PHONE_QUERY).matches) {
    delete root.dataset.fit
    grid.style.removeProperty('--fit')
    grid.style.removeProperty('grid-template-columns')
    grid.style.removeProperty('grid-template-rows')
    return
  }
  const set = (cols: number, fs: number, scrolling = false) => {
    if (scrolling) root.dataset.fit = 'scroll'
    else delete root.dataset.fit
    grid.style.gridTemplateColumns = `repeat(${cols}, minmax(0, 1fr))`
    grid.style.gridTemplateRows = scrolling ? 'none' : `repeat(${Math.ceil(n / cols)}, minmax(0, 1fr))`
    grid.style.setProperty('--fit', String(fs / BASE_FS))
  }
  let best: { cols: number; fs: number } | null = null
  for (let cols = 1; cols <= n && !(best && best.fs >= MAX_FS); cols++) {
    let lo: number = best ? best.fs + 0.25 : MIN_FS
    let hi = MAX_FS
    set(cols, lo)
    if (overflowing(grid)) continue
    set(cols, hi)
    if (!overflowing(grid)) lo = hi
    while (hi - lo > 0.25) {
      const mid = (lo + hi) / 2
      set(cols, mid)
      if (overflowing(grid)) hi = mid
      else lo = mid
    }
    best = { cols, fs: lo }
  }
  if (best) {
    set(best.cols, best.fs)
    return
  }
  // Nothing fits on one screen even at MIN_FS (a short window, many cards): MIN_FS, the most columns
  // whose cards nothing cuts off sideways (the fewest rows to scroll), and the page scrolls.
  let cols = 1
  for (let c = n; c > 1; c--) {
    set(c, MIN_FS, true)
    if (!overflowing(grid, true)) { cols = c; break }
  }
  set(cols, MIN_FS, true)
}
