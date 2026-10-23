import BadgeOutlineDemo from '@/components/shadcn-studio/badge/badge-04'
import BadgeInProgressDemo from '@/components/shadcn-studio/badge/badge-16'
import BadgeBlockedDemo from '@/components/shadcn-studio/badge/badge-17'
import BadgeCompletedDemo from '@/components/shadcn-studio/badge/badge-18'
import EmptyState from '@/components/shadcn-studio/blocks/empty-state-04/empty-state-04'
import ServiceHealthCard from '@/components/shadcn-studio/blocks/statistics-metrics-health-card'
import { accountName, barTone, inUse, resetText, status, tone, type Row } from '@/lib/accounts'
import { left, when } from '@/lib/time'
import { cn } from '@/lib/utils'

const STATUS_BADGE = { ok: BadgeCompletedDemo, warn: BadgeInProgressDemo, out: BadgeBlockedDemo }
// The block's own cell colours (the Studio chart palette), picked by the page's meaning of a limit.
const CELL_COLOR = { ok: 'var(--chart-2)', warn: 'var(--chart-4)', out: 'var(--chart-1)' }

type Props = {
  row: Row
  isBest: boolean
  now: number
  /** The Sign In action of a signed-out card the app can sign back in, else undefined. */
  signIn?: { onClick: () => void; disabled: boolean }
}

/** The account's email is its name: never cut off, it wraps at the @ onto a second line instead. */
function Name({ text }: { text: string }) {
  const at = text.indexOf('@')
  return at > 0 ? <>{text.slice(0, at)}<wbr />{text.slice(at)}</> : <>{text}</>
}

/** One account: what is left before its reset and how long until it, a status, and its limits as
 *  ten-cell battery bars (the weekly or monthly one first). A signed-out account shows its message
 *  and, when the app can sign it back in, a Sign In action. */
export function AccountCard({ row, isBest, now, signIn }: Props) {
  const name = accountName(row)
  if (row.down) {
    return (
      <EmptyState
        className='h-full'
        label={name}
        desc={row.message}
        action={signIn && { label: 'Sign In', onClick: signIn.onClick, disabled: signIn.disabled }}
      />
    )
  }
  const StatusBadge = STATUS_BADGE[tone(row)]
  const kicker = [row.isClaude ? 'Claude' : '', row.p.plan || ''].filter(Boolean).join(' · ')
  const headline = `${row.leftover}% left` + (!row.out && row.resetMs ? ` · resets ${when(row.resetMs, now)}` : '')
  const metrics = row.bars
    .filter((b): b is typeof b & { value: number } => b.value != null)
    .map(b => ({ label: b.name, percentage: b.value, detail: resetText(b.res, b.value, now), color: CELL_COLOR[barTone(b)] }))
  const using = inUse(row.p, now)
  return (
    <ServiceHealthCard
      className={cn('h-full', isBest && 'ring-2 ring-primary', row.p.stale && 'opacity-60')}
      title={<Name text={name} />}
      description={
        <>
          <span className='block'>{headline}</span>
          {[kicker, ...row.extras].filter(Boolean).join(' · ')}
        </>
      }
      action={
        <div className='flex flex-col items-end gap-1'>
          <StatusBadge title={row.noteTitle || undefined}>{status(row, isBest)}</StatusBadge>
          {using && (
            <BadgeOutlineDemo title={`Usage seen going up ${left(now - new Date(row.p.usageRoseAt!).getTime())} ago: a session is running on this account`}>
              In Use
            </BadgeOutlineDemo>
          )}
        </div>
      }
      metrics={metrics}
    />
  )
}
