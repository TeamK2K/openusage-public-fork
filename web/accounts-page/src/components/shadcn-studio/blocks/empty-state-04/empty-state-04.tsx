import { Card, CardContent, CardHeader } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { CircularProgress } from '@/components/ui/circular-progress'
import { MoveRightIcon } from "lucide-react"

import { cn } from '@/lib/utils'

type EmptyStateProps = {
  label: string
  desc: string
  action?: { label: string; onClick: () => void; disabled?: boolean }
  className?: string
}

function EmptyState({ label, desc, action, className }: EmptyStateProps) {
  return (
    <Card className={cn('pb-0', className)}>
      <CardHeader className='flex items-center gap-2'>
        <CircularProgress
          value={0}
          size={52}
          strokeWidth={5}
          showLabel
          labelClassName='text-xs'
          className='stroke-border'
        />
        <div className='flex flex-col items-start'>
          <p className='text-xl'>{label}</p>
          <p className='text-muted-foreground text-sm'>{desc}</p>
        </div>
      </CardHeader>
      {action && (
      <Card className='rounded-none border-t ring-0'>
        <CardContent className='flex justify-end'>
          <Button
            variant='link'
            size='lg'
            className='after:bg-primary relative no-underline! after:absolute after:bottom-2 after:h-px after:w-3/4 after:origin-bottom-right after:scale-x-0 after:transition-transform after:duration-300 after:ease-in-out hover:after:origin-bottom-left hover:after:scale-x-100'
            type='button'
            disabled={action.disabled}
            onClick={action.onClick}
          >
              {action.label}{' '}
              <MoveRightIcon className='inline-block' />
          </Button>
        </CardContent>
      </Card>
      )}
    </Card>
  )
}

export default EmptyState
