// The Add Account / Sign In flow. The app does the work (`/v1/accounts/…`, docs/local-http-api.md
// § Sign-in routes): it makes the seat folder and runs the login; the page follows the sign-in in a
// dialog: "Waiting for sign-in…", the sign-in link, a Paste Code box, and how it ended.

export type SignIn = {
  phase: 'idle' | 'waiting' | 'succeeded' | 'failed'
  tool?: string
  seat?: string
  folder?: string
  url?: string
  message?: string
  startedAt?: string
  signInProviderIds?: string[]
  error?: string
}

export const IDLE: SignIn = { phase: 'idle', signInProviderIds: [] }
export const TOOLS = [{ id: 'claude', label: 'Claude' }, { id: 'codex', label: 'Codex' }]
const TOOL_NAMES: Record<string, string> = { claude: 'Claude', codex: 'Codex' }
const UNREACHABLE = "OpenUsage isn't answering. Open the OpenUsage menu bar app, then try again."
const WAITING = 'Waiting for sign-in…'
const HINT = "Finish in the browser window that opened. If the page shows a code, or doesn't load, paste the code or the page's address here."

/** The current sign-in, or null when the app doesn't answer (the limits fetch shows that banner). */
export async function loadSignIn(): Promise<SignIn | null> {
  try {
    const res = await fetch('/v1/accounts/signin', { cache: 'no-store' })
    return res.ok ? ((await res.json()) as SignIn) : null
  } catch {
    return null
  }
}

/** Sends one sign-in request. Every answer, refused ones included, is the sign-in status. */
export async function postSignIn(path: string, body: object, current: SignIn): Promise<SignIn> {
  try {
    const res = await fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
    return (await res.json()) as SignIn
  } catch {
    return { ...current, error: 'unreachable', message: UNREACHABLE }
  }
}

export type SignInView = {
  shown: boolean
  waiting: boolean
  failed: boolean
  title: string
  detail: string
  notice: string
  url?: string
}

/** What the dialog shows for a sign-in status. */
export function signInView(s: SignIn): SignInView {
  const waiting = s.phase === 'waiting'
  // A refused request during a sign-in (one already running) keeps that sign-in and adds a notice.
  const refusedWhileWaiting = waiting && !!s.error
  const failed = s.phase === 'failed' || (s.phase === 'idle' && !!s.error)
  const where = [TOOL_NAMES[s.tool ?? ''] || '', s.folder || ''].filter(Boolean).join(' · ')
  const title = waiting ? WAITING : s.phase === 'succeeded' ? 'Signed In' : failed ? 'Sign-in failed' : 'Sign In'
  const detail = waiting
    ? (where ? where + '. ' : '') + (refusedWhileWaiting || s.message === WAITING ? HINT : s.message || '')
    : [where, s.message].filter(Boolean).join('. ')
  return {
    shown: s.phase !== 'idle' || !!s.message,
    waiting,
    failed,
    title,
    detail,
    notice: refusedWhileWaiting ? s.message || '' : '',
    url: waiting ? s.url : undefined
  }
}

const FIELDS = ['phase', 'tool', 'seat', 'folder', 'url', 'message', 'startedAt', 'error'] as const

/** Whether two statuses say the same thing (the 1.5 s poll mostly answers what the page already shows). */
export function sameSignIn(a: SignIn, b: SignIn): boolean {
  return FIELDS.every(k => a[k] === b[k]) && (a.signInProviderIds || []).join(',') === (b.signInProviderIds || []).join(',')
}

/** A sign-in that ended (the new card) or Sign In buttons that changed: the cards need a redraw. */
export function needsRefresh(before: SignIn, after: SignIn): boolean {
  const ended = before.phase !== after.phase && before.phase !== 'idle'
  return ended || (before.signInProviderIds || []).join(',') !== (after.signInProviderIds || []).join(',')
}
