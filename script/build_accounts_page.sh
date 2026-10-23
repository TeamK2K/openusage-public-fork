#!/usr/bin/env bash
# Rebuilds the accounts page (web/accounts-page, React + Tailwind + Shadcn Studio blocks) into the one
# self-contained HTML file the app serves at `/`: Sources/OpenUsage/Resources/accounts_page.html.
# The Swift build never runs this — the built file is committed, so `swift build` needs no Node or Bun.
#
#   script/build_accounts_page.sh          install the pinned lockfile, test, build, write the resource
#   script/build_accounts_page.sh --check  the same, but fail if the committed resource differs
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/web/accounts-page"
OUT="$ROOT/Sources/OpenUsage/Resources/accounts_page.html"

command -v bun >/dev/null 2>&1 || { echo "build_accounts_page: bun is not installed (https://bun.sh)" >&2; exit 1; }

cd "$APP"
bun install --frozen-lockfile
bun run test
bun run build

case "${1:-}" in
  --check)
    if cmp -s dist/index.html "$OUT"; then
      echo "accounts_page.html matches web/accounts-page"
    else
      echo "accounts_page.html is out of date: run script/build_accounts_page.sh and commit the result" >&2
      exit 1
    fi
    ;;
  "")
    cp dist/index.html "$OUT"
    echo "wrote ${OUT#"$ROOT"/}"
    ;;
  *)
    echo "usage: script/build_accounts_page.sh [--check]" >&2
    exit 2
    ;;
esac
