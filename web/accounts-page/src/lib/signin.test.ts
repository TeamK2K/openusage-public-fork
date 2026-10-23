import { describe, expect, it } from 'vitest'

import { IDLE, needsRefresh, signInView } from '@/lib/signin'

describe('the sign-in dialog', () => {
  it('waits with the link, the hint and the paste box', () => {
    const view = signInView({ phase: 'waiting', tool: 'claude', folder: '~/.claude-seat4', url: 'https://claude.ai/oauth', message: 'Waiting for sign-in…' })
    expect(view).toMatchObject({ shown: true, waiting: true, failed: false, title: 'Waiting for sign-in…', url: 'https://claude.ai/oauth' })
    expect(view.detail).toMatch(/^Claude · ~\/\.claude-seat4\. Finish in the browser window that opened\./)
  })

  it('keeps a running sign-in and adds a notice when a request is refused', () => {
    const view = signInView({ phase: 'waiting', tool: 'codex', error: 'sign_in_in_progress', message: 'A sign-in is already running.' })
    expect(view.waiting).toBe(true)
    expect(view.notice).toBe('A sign-in is already running.')
  })

  it('shows how it ended', () => {
    expect(signInView({ phase: 'succeeded', tool: 'claude', message: 'Added new@x.com.' })).toMatchObject({ title: 'Signed In', detail: 'Claude. Added new@x.com.', waiting: false })
    expect(signInView({ phase: 'failed', message: 'claude not found' })).toMatchObject({ title: 'Sign-in failed', failed: true })
    expect(signInView({ phase: 'idle', error: 'unreachable', message: "OpenUsage isn't answering." })).toMatchObject({ shown: true, failed: true })
    expect(signInView(IDLE).shown).toBe(false)
  })

  it('redraws the cards when a sign-in ends or the Sign In buttons change', () => {
    expect(needsRefresh({ phase: 'waiting' }, { phase: 'succeeded' })).toBe(true)
    expect(needsRefresh(IDLE, { phase: 'waiting' })).toBe(false)
    expect(needsRefresh(IDLE, { phase: 'idle', signInProviderIds: ['claude@a'] })).toBe(true)
  })
})
