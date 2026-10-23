import { describe, expect, it } from 'vitest'

import { left, when } from '@/lib/time'

const minute = 60_000
const hour = 60 * minute
const day = 24 * hour

describe('the page time format', () => {
  it('is relative, in one format', () => {
    expect(left(45 * minute)).toBe('45m')
    expect(left(2 * hour + 29 * minute)).toBe('2h 29m')
    expect(left(12 * hour + 48 * minute)).toBe('12h 48m')
    expect(left(3 * hour)).toBe('3h')
    expect(left(0)).toBe('now')
  })

  it('drops minutes a day out and hours ten days out', () => {
    expect(left(2 * day + 4 * hour + 20 * minute)).toBe('2d 4h')
    expect(left(6 * day)).toBe('6d')
    expect(left(13 * day + 5 * hour)).toBe('13d')
  })

  it('says "in …" before an instant and "now" after it', () => {
    const now = 1_000_000_000
    expect(when(now + 2 * hour + 29 * minute + 20_000, now)).toBe('in 2h 29m')
    expect(when(now - 1000, now)).toBe('now')
  })
})
