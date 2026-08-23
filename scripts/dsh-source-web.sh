#!/usr/bin/env bash
set -euo pipefail

if [ ! -f package.json ] || [ ! -f apps/cli/src/bin.ts ]; then
  echo "Run this from the deepseek-harness source root." >&2
  exit 1
fi

PORT="${DSH_SOURCE_PORT:-3081}"
exec pnpm dsh web --no-open --port "${PORT}"
