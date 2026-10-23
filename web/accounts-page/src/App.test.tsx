// @vitest-environment happy-dom
import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { App } from '@/App'
import type { Limits } from '@/lib/accounts'
import type { SignIn } from '@/lib/signin'

const now = Date.now()
const iso = (offsetMs: number) => new Date(now + offsetMs).toISOString()
const pct = (remaining: number, resetsIn: number, windowSeconds = 7 * 86400) => ({
  kind: 'consumption', unit: 'percent', used: 100 - remaining, limit: 100, remaining, resetsAt: iso(resetsIn), windowSeconds
})

const limits: Limits = {
  providers: {
    'claude@a': {
      displayName: 'Claude: a@x.com', plan: 'Max', fetchedAt: iso(-10_000), usageRoseAt: iso(-60_000),
      resources: { session: pct(80, 3_600_000, 18000), weekly: pct(64, 2 * 86_400_000) }
    }
  },
  errors: [{ providerId: 'claude@gone', displayName: 'Claude: gone@x.com', message: 'Signed Out. Last signed in at ~/.claude-seat2.' }]
}

type Call = { url: string; method: string; body: unknown }

function serve(answers: { limits?: Limits | 'down'; signIn?: SignIn; post?: (call: Call) => SignIn }) {
  const calls: Call[] = []
  let signIn: SignIn = answers.signIn ?? { phase: 'idle', signInProviderIds: ['claude@gone'] }
  vi.stubGlobal('fetch', vi.fn(async (url: string, init?: RequestInit) => {
    const call = { url, method: init?.method ?? 'GET', body: init?.body ? JSON.parse(String(init.body)) : undefined }
    calls.push(call)
    if (url === '/v1/limits') {
      if (answers.limits === 'down') throw new TypeError('Failed to fetch')
      return Response.json(answers.limits ?? limits)
    }
    if (call.method === 'POST' && answers.post) signIn = answers.post(call)
    return Response.json(signIn)
  }))
  return calls
}

beforeEach(() => {
  vi.stubGlobal('matchMedia', (query: string) => ({ matches: false, media: query, addEventListener() {}, removeEventListener() {} }))
})
afterEach(() => { cleanup(); vi.unstubAllGlobals() })

describe('the accounts page', () => {
  it('names the account to use and shows its card, status, In Use badge and battery bars', async () => {
    serve({})
    render(<App />)
    expect(await screen.findByText('Use a@x.com')).toBeTruthy()
    expect(screen.getByText(/64% left, resets in 2d/)).toBeTruthy()
    expect(screen.getByText('Use this one')).toBeTruthy()
    expect(screen.getByText('In Use')).toBeTruthy()
    expect(screen.getByText('Weekly')).toBeTruthy()
    expect(screen.getByText('Session')).toBeTruthy()
    expect(screen.getByText(/refreshes every 30 seconds/)).toBeTruthy()
    // Fitting scales the card grid only: the top bar (Add Account) sits outside it and the page's
    // base size is never touched, so the bar looks the same whatever the cards need.
    const add = screen.getByRole('button', { name: /Add Account/ })
    expect(add.closest('#cards')).toBeNull()
    expect(document.documentElement.style.fontSize).toBe('')
  })

  it('signs a signed-out card back in', async () => {
    const calls = serve({ post: () => ({ phase: 'waiting', tool: 'claude', folder: '~/.claude-seat2', message: 'Waiting for sign-in…' }) })
    render(<App />)
    expect(await screen.findByText('Signed Out. Last signed in at ~/.claude-seat2.')).toBeTruthy()
    fireEvent.click(await screen.findByRole('button', { name: /Sign In/ }))
    await waitFor(() => expect(calls.some(c => c.url === '/v1/accounts/signin' && c.method === 'POST')).toBe(true))
    expect(calls.find(c => c.method === 'POST')?.body).toEqual({ providerId: 'claude@gone' })
    expect(await screen.findByText('Waiting for sign-in…')).toBeTruthy()
  })

  it('adds an account, takes a pasted code, and cancels', async () => {
    const calls = serve({
      post: call => call.url.endsWith('/cancel')
        ? { phase: 'idle', signInProviderIds: [] }
        : { phase: 'waiting', tool: 'codex', folder: '~/.codex-seat3', url: 'https://auth.example/login', message: 'Waiting for sign-in…' }
    })
    render(<App />)
    await screen.findByText('Use a@x.com')
    const add = screen.getByRole('button', { name: /Add Account/ })
    fireEvent.pointerDown(add, { button: 0, ctrlKey: false, pointerType: 'mouse' })
    fireEvent.click(await screen.findByRole('menuitem', { name: 'Codex' }))
    await waitFor(() => expect(calls.find(c => c.url === '/v1/accounts/add')?.body).toEqual({ tool: 'codex' }))

    expect(await screen.findByText('Waiting for sign-in…')).toBeTruthy()
    expect(screen.getByRole('link', { name: 'Open Sign-In Page' }).getAttribute('href')).toBe('https://auth.example/login')
    fireEvent.change(screen.getByLabelText('Sign-in code'), { target: { value: 'abc-123' } })
    fireEvent.click(screen.getByRole('button', { name: 'Paste Code' }))
    await waitFor(() => expect(calls.find(c => c.url === '/v1/accounts/signin/code')?.body).toEqual({ code: 'abc-123' }))

    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }))
    await waitFor(() => expect(calls.some(c => c.url === '/v1/accounts/signin/cancel')).toBe(true))
    await waitFor(() => expect(screen.queryByText('Waiting for sign-in…')).toBeNull())
  })

  it('says so when the app is not answering', async () => {
    serve({ limits: 'down' })
    await act(async () => { render(<App />) })
    expect(await screen.findByText(/OpenUsage isn't answering on this Mac/)).toBeTruthy()
  })
})
