import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react'

import { AccountCard } from '@/components/account-card'
import AuthenticatorDialog from '@/components/shadcn-studio/blocks/dashboard-dialog-08/dialog-authenticator'
import DropdownMenuAlignStartDemo from '@/components/shadcn-studio/dropdown-menu/dropdown-menu-09'
import { buildPage, type Limits } from '@/lib/accounts'
import { fit } from '@/lib/fit'
import { IDLE, loadSignIn, needsRefresh, postSignIn, signInView, TOOLS, type SignIn } from '@/lib/signin'

const REFRESH_MS = 30_000
const SIGN_IN_POLL_MS = 1_500

/** The accounts page: a top bar (title, Add Account), the which-account verdict, one card per account
 *  fitted on one screen (soonest reset first), and a one-line footer. Layout: dashboard-header-09. */
export function App() {
  const [limits, setLimits] = useState<Limits | null>(null)
  const [unreachable, setUnreachable] = useState(false)
  const [signIn, setSignIn] = useState<SignIn>(IDLE)
  const [now, setNow] = useState(() => Date.now())
  const signInRef = useRef<SignIn>(IDLE)
  const grid = useRef<HTMLDivElement>(null)

  const refreshLimits = useCallback(async () => {
    try {
      const res = await fetch('/v1/limits', { cache: 'no-store' })
      if (!res.ok) throw new Error(`limits answered ${res.status}`)
      setLimits((await res.json()) as Limits)
      setUnreachable(false)
    } catch {
      setUnreachable(true)
    }
    setNow(Date.now())
  }, [])

  const showSignIn = useCallback((next: SignIn) => {
    const before = signInRef.current
    signInRef.current = next
    setSignIn(next)
    if (needsRefresh(before, next)) void refreshLimits()
  }, [refreshLimits])

  const refresh = useCallback(async () => {
    const [, s] = await Promise.all([refreshLimits(), loadSignIn()])
    if (s) showSignIn(s)
  }, [refreshLimits, showSignIn])

  const send = useCallback(async (path: string, body: object = {}) => {
    const answer = await postSignIn(path, body, signInRef.current)
    showSignIn(answer)
    return answer
  }, [showSignIn])

  useEffect(() => {
    void refresh()
    const timer = setInterval(() => void refresh(), REFRESH_MS)
    const onVisible = () => { if (!document.hidden) void refresh() }
    document.addEventListener('visibilitychange', onVisible)
    return () => { clearInterval(timer); document.removeEventListener('visibilitychange', onVisible) }
  }, [refresh])

  const view = signInView(signIn)
  useEffect(() => {
    if (!view.waiting) return
    const poll = setInterval(async () => { const s = await loadSignIn(); if (s) showSignIn(s) }, SIGN_IN_POLL_MS)
    return () => clearInterval(poll)
  }, [view.waiting, showSignIn])

  const page = limits ? buildPage(limits, now) : null
  // Fit after every render, and again two frames later, once the charts have measured themselves
  // (they first draw at a placeholder size).
  useLayoutEffect(() => {
    fit(grid.current)
    let frame = requestAnimationFrame(() => { frame = requestAnimationFrame(() => fit(grid.current)) })
    return () => cancelAnimationFrame(frame)
  })
  // And whenever the window, the grid or the loaded font changes the room there is.
  useEffect(() => {
    let frame = 0
    const refit = () => { cancelAnimationFrame(frame); frame = requestAnimationFrame(() => fit(grid.current)) }
    window.addEventListener('resize', refit)
    const observer = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(refit)
    if (grid.current) observer?.observe(grid.current)
    void document.fonts?.ready.then(refit)
    return () => { cancelAnimationFrame(frame); window.removeEventListener('resize', refit); observer?.disconnect() }
  }, [])

  const canSignIn = new Set(signIn.signInProviderIds || [])
  return (
    <div id='page' className='flex min-h-dvh flex-col sm:h-dvh'>
      <header className='bg-card sticky top-0 z-50 border-b'>
        <div className='mx-auto flex max-w-7xl items-center justify-between gap-6 px-4 py-2 sm:px-6'>
          <span className='text-xl font-semibold'>AI Accounts</span>
          <DropdownMenuAlignStartDemo
            label='Add Account'
            items={TOOLS}
            disabled={view.waiting}
            onSelect={tool => void send('/v1/accounts/add', { tool })}
          />
        </div>
      </header>
      <main className='mx-auto flex size-full min-h-0 max-w-7xl flex-1 flex-col gap-4 px-4 py-6 sm:px-6'>
        <div className='flex flex-col gap-1'>
          <h1 className='text-2xl font-semibold'>
            {page ? page.verdict.lead : 'Loading…'}
            {page?.verdict.dim && <span className='text-muted-foreground font-normal'>{page.verdict.dim}</span>}
          </h1>
          {page?.sub && <p className='text-muted-foreground text-sm'>{page.sub}</p>}
          {unreachable && (
            <p className='text-destructive text-sm'>
              OpenUsage isn't answering on this Mac. Open the OpenUsage menu bar app, then this page refreshes by itself.
            </p>
          )}
        </div>
        <div ref={grid} id='cards' className='flex flex-col gap-4 sm:grid sm:min-h-0 sm:flex-1'>
          {page?.rows.map(row => (
            <AccountCard
              key={row.id}
              row={row}
              isBest={row === page.best}
              now={now}
              signIn={canSignIn.has(row.id)
                ? { onClick: () => void send('/v1/accounts/signin', { providerId: row.id }), disabled: view.waiting }
                : undefined}
            />
          ))}
        </div>
      </main>
      <footer className='bg-card h-10 border-t'>
        <div className='text-muted-foreground mx-auto flex size-full max-w-7xl items-center gap-4 px-4 text-sm sm:px-6'>
          <span>{page?.footer ?? ''}</span>
          {page?.issues && <span className='text-amber-600 dark:text-amber-400'>{page.issues}</span>}
        </div>
      </footer>
      <AuthenticatorDialog
        open={view.shown}
        title={view.title}
        description={view.detail}
        notice={view.notice}
        failed={view.failed}
        waiting={view.waiting}
        url={view.url}
        onPaste={async code => !(await send('/v1/accounts/signin/code', { code })).error}
        onDismiss={() => void send('/v1/accounts/signin/cancel')}
      />
    </div>
  )
}
