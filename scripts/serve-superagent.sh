#!/usr/bin/env bash
# Foreground dsh-superagent process for the Coolify sidecar.
set -euo pipefail

setup-superagent

host="${DSH_TRUSTED_HOST:?Set DSH_TRUSTED_HOST or let entrypoint discover MagicDNS}"
port="${DSH_SUPERAGENT_PORT:-3082}"
https_port="${DSH_SUPERAGENT_HTTPS_PORT:-8443}"
profile="${DSH_SUPERAGENT_PROFILE:-superagent}"

args=(
  dsh --profile "${profile}" --no-open
  --port "${port}"
  --trusted-host "${host}"
)

if [[ "${host}" != *:* ]]; then
  args+=(--trusted-host "${host}:${https_port}")
  args+=(--public-url "https://${host}:${https_port}/")
  echo "dsh-superagent panel: https://${host}:${https_port}/"
else
  args+=(--public-url "https://${host}/")
  echo "dsh-superagent panel: https://${host}/"
fi

export PATH="${HOME}/.local/bin:${PATH}"
exec "${args[@]}"
