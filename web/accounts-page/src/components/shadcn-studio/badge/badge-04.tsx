import type { ComponentProps } from 'react'

import { Badge } from '@/components/ui/badge'

const BadgeOutlineDemo = (props: ComponentProps<typeof Badge>) => {
  return <Badge variant='outline' {...props} />
}

export default BadgeOutlineDemo
