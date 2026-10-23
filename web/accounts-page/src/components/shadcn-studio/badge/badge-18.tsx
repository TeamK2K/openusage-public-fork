import type { ComponentProps } from 'react'

import { Badge } from '@/components/ui/badge'

const BadgeCompletedDemo = ({ children, ...props }: ComponentProps<typeof Badge>) => {
  return (
    <Badge {...props} className='border-none bg-green-600/10 text-green-600 focus-visible:ring-green-600/20 focus-visible:outline-none dark:bg-green-400/10 dark:text-green-400 dark:focus-visible:ring-green-400/40 [a]:hover:bg-green-600/5 dark:[a]:hover:bg-green-400/5'>
      <span className='size-1.5 rounded-full bg-green-600 dark:bg-green-400' aria-hidden='true' />
      {children}
    </Badge>
  )
}

export default BadgeCompletedDemo
