import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuTrigger
} from '@/components/ui/dropdown-menu'
import { PlusIcon } from "lucide-react"

type Props = {
  label: string
  items: { id: string; label: string }[]
  onSelect: (id: string) => void
  disabled?: boolean
}

const DropdownMenuAlignStartDemo = ({ label, items, onSelect, disabled }: Props) => {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button disabled={disabled}>
          <PlusIcon
          />
          {label}
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent className='w-34' align='end'>
        <DropdownMenuGroup>
          {items.map(item => (
            <DropdownMenuItem key={item.id} onSelect={() => onSelect(item.id)}>
              {item.label}
            </DropdownMenuItem>
          ))}
        </DropdownMenuGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

export default DropdownMenuAlignStartDemo
