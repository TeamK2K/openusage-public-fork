import { readFileSync } from 'node:fs'

import { describe, expect, it } from 'vitest'

const css = readFileSync(new URL('./index.css', import.meta.url), 'utf8')

function block(selector: string): string {
  const start = css.indexOf(`\n${selector} {`)
  expect(start, selector).toBeGreaterThan(-1)
  return css.slice(start, css.indexOf('}', start))
}

function oklch(scope: string, name: string): { l: number; c: number; h: number } {
  const m = scope.match(new RegExp(`--${name}: oklch\\(([\\d.]+) ([\\d.]+) ([\\d.]+)\\)`))
  expect(m, name).not.toBeNull()
  return { l: Number(m![1]), c: Number(m![2]), h: Number(m![3]) }
}

describe('the battery cell colours', () => {
  // chart-1 / 2 / 4 are the block's red / green / amber cells.
  it('keep the same hues in dark mode, bright enough for the dark card', () => {
    const light = block(':root')
    const dark = block('.dark')
    for (const name of ['chart-1', 'chart-2', 'chart-4']) {
      const l = oklch(light, name)
      const d = oklch(dark, name)
      expect(d.h, name).toBeCloseTo(l.h, 0)
      expect(d.c, name).toBeGreaterThan(0.1)
      // The dark card is oklch(0.205 0 0): a filled cell needs a clearly lighter colour.
      expect(d.l, name).toBeGreaterThanOrEqual(0.7)
    }
  })
})

describe('fit to screen', () => {
  it('scales only the card grid, so the top bar keeps one size', () => {
    const cards = block('#cards')
    for (const token of ['--spacing', '--text-xs', '--text-sm', '--text-base', '--text-xl']) {
      expect(cards).toMatch(new RegExp(`${token}: calc\\([^;]*var\\(--fit, 1\\)\\)`))
    }
  })

  it('shrinks the top bar and verdict with the window height, never by theme', () => {
    const page = block('#page')
    for (const token of ['--spacing', '--text-sm', '--text-xl', '--text-2xl']) {
      expect(page).toMatch(new RegExp(`${token}: clamp\\([^;]*vh[^;]*\\)`))
    }
    expect(block('.dark')).not.toMatch(/--(spacing|text-)/)
  })
})
