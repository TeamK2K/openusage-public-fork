import type { ComponentProps } from 'react'

import { Badge } from '@/components/ui/badge'

const BadgeBlockedDemo = ({ children, ...props }: ComponentProps<typeof Badge>) => {
  return (
    <Badge {...props} className='bg-destructive/10 text-destructive focus-visible:ring-destructive/20 dark:focus-visible:ring-destructive/40 [a]:hover:bg-destructive/5 border-none focus-visible:outline-none'>
      <span className='bg-destructive size-1.5 rounded-full' aria-hidden='true' />
      {children}
    </Badge>
  )
}

export default BadgeBlockedDemo
