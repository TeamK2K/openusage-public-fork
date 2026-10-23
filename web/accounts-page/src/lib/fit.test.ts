// @vitest-environment happy-dom
import { afterEach, describe, expect, it } from 'vitest'

import { overflowing } from '@/lib/fit'

// happy-dom does no layout, so each box gets the sizes a browser would measure.
function box(tag: string, size: { cw: number; ch: number; sw?: number; sh?: number }, ...children: HTMLElement[]) {
  const e = document.createElement(tag)
  Object.defineProperties(e, {
    clientWidth: { value: size.cw }, clientHeight: { value: size.ch },
    scrollWidth: { value: size.sw ?? size.cw }, scrollHeight: { value: size.sh ?? size.ch }
  })
  e.append(...children)
  return e
}

function grid(...cards: HTMLElement[]) {
  const g = document.createElement('div')
  g.append(...cards)
  document.body.append(g)
  return g
}

afterEach(() => { document.body.textContent = '' })

describe('overflowing', () => {
  it('passes cards whose content fits', () => {
    const card = box('div', { cw: 200, ch: 150 }, box('p', { cw: 80, ch: 20 }), box('div', { cw: 120, ch: 36 }))
    expect(overflowing(grid(card))).toBe(false)
  })

  it('counts a card with a clipped child as overflowing, though the card itself fits', () => {
    // "37%" / "resets in 2h" cut off: the text's box is narrower than what it holds.
    const text = box('p', { cw: 40, ch: 20, sw: 74 })
    const card = box('div', { cw: 200, ch: 150 }, box('div', { cw: 60, ch: 40 }, text))
    expect(overflowing(grid(card))).toBe(true)
  })

  it('counts a chart row taller than its box as overflowing', () => {
    const card = box('div', { cw: 200, ch: 150 }, box('div', { cw: 80, ch: 36, sh: 60 }))
    expect(overflowing(grid(card))).toBe(true)
  })

  it('counts a card taller than its cell, unless the page may scroll', () => {
    const card = box('div', { cw: 200, ch: 150, sh: 220 }, box('p', { cw: 80, ch: 20 }))
    const g = grid(card)
    expect(overflowing(g)).toBe(true)
    expect(overflowing(g, true)).toBe(false)
  })

  it('still counts sideways clipping when the page may scroll', () => {
    const card = box('div', { cw: 200, ch: 150, sw: 260 })
    expect(overflowing(grid(card), true)).toBe(true)
  })

  it('ignores inline and SVG boxes, which report no size', () => {
    const card = box('div', { cw: 200, ch: 150 }, box('span', { cw: 0, ch: 0, sw: 0, sh: 0 }))
    expect(overflowing(grid(card))).toBe(false)
  })
})
