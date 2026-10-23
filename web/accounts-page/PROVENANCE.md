# Accounts page — provenance

The page the app serves at `/` (docs/local-http-api.md § `GET /`). React + Tailwind v4 + shadcn/ui,
composed from Shadcn Studio Pro items installed with the shadcn CLI (`components.json`, style
`radix-nova`, base `radix`, preset `nova`, icons `lucide`) and installed as shipped: only data wiring,
copy, routes and import aliases changed, each listed below.

Rebuild: `script/build_accounts_page.sh` (pinned `bun.lock`, runs the Vitest suite, writes
`Sources/OpenUsage/Resources/accounts_page.html`); `--check` proves the committed file matches.

## Studio items

| Studio slug | Installed file | Used by | Changes from the shipped file |
| --- | --- | --- | --- |
| `@ss-blocks/statistics-component-22` | `src/components/shadcn-studio/blocks/statistics-metrics-health-card.tsx` | `src/components/account-card.tsx` (every account card) | `title` widened to a React node; optional `description` and `action` render in the card primitive's `CardDescription` / `CardAction` slots (name line, status badges); optional `color` on a metric picks its filled cells' colour (the page passes chart-2 / chart-4 / chart-1 for 25%+ left / under 25% / at 0 or running out, instead of the block's 75% / 40% bands). Bar markup, whole-cell fill and layout as shipped. |
| `@ss-blocks/empty-state-04` | `src/components/shadcn-studio/blocks/empty-state-04/empty-state-04.tsx` | `src/components/account-card.tsx` (signed-out cards) | `next/link` "View more" link → a `Button` with an `action` prop (Sign In); the footer renders only when there is an action; `className` passed through. |
| `@ss-blocks/dashboard-dialog-08` | `src/components/shadcn-studio/blocks/dashboard-dialog-08/dialog-authenticator.tsx` | `src/App.tsx` (Add Account / Sign In dialog) | Controlled `open` instead of a trigger; copy and the field wired to the sign-in flow (title, detail, notice, Open Sign-In Page link, sign-in code field, Paste Code, Cancel / Close); outside clicks don't dismiss. |
| `@ss-blocks/dashboard-header-09` | — (layout only) | `src/App.tsx` | The page shell (sticky `bg-card` header, `max-w-7xl` main, `bg-card h-10` footer) from the block's page; its logo, search, language, activity, notification and profile sub-blocks are not installed. Title and Add Account in the header. |
| `@ss-components/dropdown-menu-09` | `src/components/shadcn-studio/dropdown-menu/dropdown-menu-09.tsx` | `src/App.tsx` (Add Account → Claude / Codex) | Demo items → `items` / `onSelect` props, trigger label and plus icon, end-aligned. |
| `@ss-components/badge-18` | `src/components/shadcn-studio/badge/badge-18.tsx` | `src/components/account-card.tsx` (status: ready) | Label from `children`; props passed through. |
| `@ss-components/badge-16` | `src/components/shadcn-studio/badge/badge-16.tsx` | `src/components/account-card.tsx` (status: low / runs out) | Label from `children`; props passed through. |
| `@ss-components/badge-17` | `src/components/shadcn-studio/badge/badge-17.tsx` | `src/components/account-card.tsx` (status: out) | Label from `children`; props passed through. |
| `@ss-components/badge-04` | `src/components/shadcn-studio/badge/badge-04.tsx` | `src/components/account-card.tsx` (In Use) | Props passed through. |

shadcn/ui primitives in `src/components/ui/` (`badge`, `button`, `card`, `chart`, `circular-progress`,
`dialog`, `dropdown-menu`, `input`, `label`) came in as these items' registry dependencies, unchanged.
`src/index.css` is the `nova` preset's theme as written by `shadcn init`, with the Shadcn Studio chart
palette (`--chart-1..5`, read from shadcnstudio.com 2026-10-23) in place of the preset's greys,
because the battery bars colour by those variables. In `.dark`, chart-1 / 2 / 4 keep the light hues
(red-orange / green / amber) lifted for contrast on the dark card, because Studio's dark chart palette
is blue / green / purple. A `#cards` rule scales the grid's spacing, text and radius tokens by `--fit`
(set by `src/lib/fit.ts`), so fitting to the screen resizes the cards only, never the top bar.

## App code (not from Studio)

- `src/lib/` — the page's logic ported from the hand-written page: time format, card rows and order,
  verdict, sign-in states, fit-to-screen. Tested by `src/lib/*.test.ts`.
- `src/components/account-card.tsx`, `src/App.tsx`, `src/main.tsx` — data wiring of the items above.
