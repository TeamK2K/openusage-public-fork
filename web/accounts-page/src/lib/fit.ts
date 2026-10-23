// Fit every card on one screen at the biggest text that leaves nothing cut off: for each column count,
// search the root font size (every size on the page is in rem, so it scales the whole page) at which
// no card clips or overflows, and keep the column count that allows the biggest one. Measured, not
// estimated, so it holds for any card mix. Phones get one card per row and the page scrolls.

const MIN_FS = 8
const MAX_FS = 26
export const PHONE_QUERY = '(max-width: 639px)'

function overflowing(grid: HTMLElement): boolean {
  for (const child of Array.from(grid.children)) {
    const card = child as HTMLElement
    if (card.scrollHeight > card.clientHeight + 1 || card.scrollWidth > card.clientWidth + 1) return true
  }
  const page = document.documentElement
  return page.scrollHeight > window.innerHeight + 1 || page.scrollWidth > window.innerWidth + 1
}

export function fit(grid: HTMLElement | null): void {
  const root = document.documentElement
  if (!grid) return
  const n = grid.children.length
  if (!n || matchMedia(PHONE_QUERY).matches) {
    root.style.removeProperty('font-size')
    grid.style.removeProperty('grid-template-columns')
    grid.style.removeProperty('grid-template-rows')
    return
  }
  const set = (cols: number, fs: number) => {
    grid.style.gridTemplateColumns = `repeat(${cols}, minmax(0, 1fr))`
    grid.style.gridTemplateRows = `repeat(${Math.ceil(n / cols)}, minmax(0, 1fr))`
    root.style.fontSize = `${fs}px`
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
  // Nothing fits even at the smallest size (a tiny window): the smallest size, about square.
  if (!best) best = { cols: Math.min(n, Math.ceil(Math.sqrt(n * 1.5))), fs: MIN_FS }
  set(best.cols, best.fs)
}
