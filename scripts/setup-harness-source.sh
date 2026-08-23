#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-$HOME/workspace/deepseek-harness}"
REPOSITORY="https://github.com/deepseek-ai/deepseek-harness.git"

if [ -e "${TARGET}" ] && [ ! -d "${TARGET}/.git" ]; then
  echo "Target exists but is not a Git checkout: ${TARGET}" >&2
  exit 1
fi

if [ ! -d "${TARGET}/.git" ]; then
  git clone "${REPOSITORY}" "${TARGET}"
fi

cd "${TARGET}"
git fetch --prune origin
corepack enable
pnpm install
pnpm run typecheck

printf '\nSource checkout ready at %s\n' "${TARGET}"
printf 'Build everything: cd %s && pnpm run build\n' "${TARGET}"
printf 'Run source UI:  cd %s && dsh-source-web\n' "${TARGET}"
