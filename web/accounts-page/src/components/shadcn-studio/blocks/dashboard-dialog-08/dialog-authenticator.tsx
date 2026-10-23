import { useState, type FormEvent } from 'react'

import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

import { cn } from '@/lib/utils'

type Props = {
  open: boolean
  title: string
  description: string
  notice?: string
  failed?: boolean
  /** While a sign-in waits: the sign-in page link (once the login printed it) and the Paste Code box. */
  waiting: boolean
  url?: string
  /** Passes the pasted code on; resolves true when it was accepted, so the box clears. */
  onPaste: (code: string) => Promise<boolean>
  /** Cancel (a waiting sign-in) or Close (one that ended). */
  onDismiss: () => void
  className?: string
}

const AuthenticatorDialog = ({ open, title, description, notice, failed, waiting, url, onPaste, onDismiss, className }: Props) => {
  const [code, setCode] = useState('')

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    if (await onPaste(code)) setCode('')
  }

  return (
    <Dialog open={open} onOpenChange={next => { if (!next) onDismiss() }}>
      <DialogContent
        className={cn('sm:max-w-145 [&>[data-slot=dialog-close]>svg]:size-5', className)}
        onInteractOutside={e => e.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle className={cn('text-lg leading-7 font-semibold', failed && 'text-destructive')}>{title}</DialogTitle>
          <DialogDescription className='max-w-sm'>
            {description}
          </DialogDescription>
          {notice && <p className='text-sm text-amber-600 dark:text-amber-400'>{notice}</p>}
        </DialogHeader>

        {waiting && url && (
          <Button variant='outline' size='lg' asChild>
            <a href={url} target='_blank' rel='noopener'>Open Sign-In Page</a>
          </Button>
        )}

        {waiting && (
          <form id='sign-in-code' className='space-y-2' onSubmit={submit}>
            <Label htmlFor='code'>Sign-in code</Label>
            <Input
              id='code'
              autoComplete='off'
              spellCheck={false}
              value={code}
              onChange={e => setCode(e.target.value)}
              placeholder="Paste the code, or the address of a page that didn't load"
            />
          </form>
        )}

        <div className='flex gap-4 sm:flex-row sm:justify-end'>
          {waiting && <Button size='lg' type='submit' form='sign-in-code'>Paste Code</Button>}
          <Button variant='outline' size='lg' onClick={onDismiss}>
            {waiting ? 'Cancel' : 'Close'}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

export default AuthenticatorDialog
