#!/usr/bin/env bash
# Install dsh-superagent into its own persistent profile. Safe to re-run.
# Does not replace cordis.patch.yml once it contains a dsh-superagent entry,
# and does not recreate an existing profile (that would delete machine config).
set -euo pipefail

DSH_HOME="${DSH_HOME:-${HOME}/.dsh}"
TARGET="${DSH_SUPERAGENT_DIR:-/opt/dsh-superagent-prototype}"
PROFILE="${DSH_SUPERAGENT_PROFILE:-superagent}"
PORT="${DSH_SUPERAGENT_PORT:-3082}"
STATE_DIR="${DSH_SUPERAGENT_STATE_DIR:-${DSH_HOME}/state/${PROFILE}}"
REPO="${DSH_SUPERAGENT_REPOSITORY:-https://github.com/deepseek-ai/dsh-superagent-prototype.git}"
REF="${DSH_SUPERAGENT_REF:-6337fc823ce20251c8de8085948165c81aaa701e}"
PROFILE_DIR="${DSH_HOME}/profiles/${PROFILE}"
export DSH_HOME

checkout_ref() {
  git -C "${TARGET}" fetch --prune origin
  if git -C "${TARGET}" rev-parse --verify --quiet "refs/remotes/origin/${REF}" >/dev/null; then
    git -C "${TARGET}" checkout --detach "origin/${REF}"
  else
    git -C "${TARGET}" checkout --detach "${REF}"
  fi
}

if [ ! -f "${TARGET}/package.json" ]; then
  mkdir -p "$(dirname "${TARGET}")"
  git clone "${REPO}" "${TARGET}"
  checkout_ref
elif [ "${DSH_SUPERAGENT_AUTO_UPDATE:-0}" = "1" ]; then
  checkout_ref
fi

if [ ! -f "${TARGET}/lib/index.js" ] || [ "${DSH_SUPERAGENT_AUTO_UPDATE:-0}" = "1" ]; then
  echo "Building dsh-superagent at ${TARGET}"
  (cd "${TARGET}" && pnpm install --frozen-lockfile && pnpm build)
fi

mkdir -p "${STATE_DIR}" "${HOME}/.local/bin"
chmod 700 "${STATE_DIR}"
if [ ! -e "${HOME}/.local/bin/gh-agent" ]; then
  cat > "${HOME}/.local/bin/gh-agent" <<'EOF'
#!/bin/sh
GH_CONFIG_DIR="${HOME}/.config/gh-agent" exec gh "$@"
EOF
  chmod 755 "${HOME}/.local/bin/gh-agent"
fi

if [ ! -f "${PROFILE_DIR}/package.json" ]; then
  echo "Creating ${PROFILE} profile from the Web template"
  dsh "${PROFILE}" --from-default-profile web --dump-config >/dev/null
fi

stamp="${PROFILE_DIR}/.coolify-install-stamp"
want="$(dsh --version) $(git -C "${TARGET}" rev-parse HEAD)"
if ! grep -q 'dsh-superagent' "${PROFILE_DIR}/package.json" 2>/dev/null \
  || [ "$(cat "${stamp}" 2>/dev/null || true)" != "${want}" ]; then
  echo "Linking dsh-superagent into profile ${PROFILE}"
  dsh plugin --profile "${PROFILE}" add "link:${TARGET}"
  printf '%s\n' "${want}" > "${stamp}"
fi

patch="${PROFILE_DIR}/cordis.patch.yml"
if [ ! -f "${patch}" ] || ! grep -q 'id: dsh-superagent' "${patch}"; then
  cat > "${patch}" <<EOF
# Machine configuration for this Coolify instance. Edit limits in
# Settings -> Deployment after the first start. Do not remove the
# dsh-superagent row; setup-superagent will not overwrite this file
# once that row exists.
- id: webserver
  config:
    host: 127.0.0.1
    port: ${PORT}
- id: dsh-superagent
  config:
    stateDir: ${STATE_DIR}
EOF
  echo "Wrote ${patch}"
fi

printf 'dsh-superagent profile ready (%s)\n' "${want}"
