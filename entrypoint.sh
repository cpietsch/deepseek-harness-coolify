#!/usr/bin/env bash
set -euo pipefail

USERNAME="${USERNAME:-dev}"
USER_HOME="/home/${USERNAME}"

mkdir -p "${USER_HOME}/.ssh" "${USER_HOME}/.dsh" "${USER_HOME}/workspace" /run/sshd /etc/ssh/hostkeys
chown -R "${USERNAME}:${USERNAME}" "${USER_HOME}/.ssh" "${USER_HOME}/.dsh" "${USER_HOME}/workspace"

if [ -n "${SSH_AUTHORIZED_KEYS:-}" ]; then
  printf '%s\n' "${SSH_AUTHORIZED_KEYS}" > "${USER_HOME}/.ssh/authorized_keys"
fi
chmod 700 "${USER_HOME}/.ssh"
if [ -f "${USER_HOME}/.ssh/authorized_keys" ]; then
  chmod 600 "${USER_HOME}/.ssh/authorized_keys"
  chown "${USERNAME}:${USERNAME}" "${USER_HOME}/.ssh/authorized_keys"
fi

if [ ! -f /etc/ssh/hostkeys/ssh_host_ed25519_key ]; then
  ssh-keygen -q -t ed25519 -N '' -f /etc/ssh/hostkeys/ssh_host_ed25519_key
fi
if [ ! -f /etc/ssh/hostkeys/ssh_host_ecdsa_key ]; then
  ssh-keygen -q -t ecdsa -N '' -f /etc/ssh/hostkeys/ssh_host_ecdsa_key
fi
if [ ! -f /etc/ssh/hostkeys/ssh_host_rsa_key ]; then
  ssh-keygen -q -t rsa -b 4096 -N '' -f /etc/ssh/hostkeys/ssh_host_rsa_key
fi

if [ -n "${DOCKER_CERT_PATH:-}" ]; then
  echo "Waiting for isolated Docker daemon certificates..."
  for _ in $(seq 1 90); do
    if [ -r "${DOCKER_CERT_PATH}/ca.pem" ] && [ -r "${DOCKER_CERT_PATH}/cert.pem" ] && [ -r "${DOCKER_CERT_PATH}/key.pem" ]; then
      break
    fi
    sleep 1
  done
fi

cat > /etc/profile.d/dev-runtime.sh <<EOF
export DSH_HOME="${DSH_HOME:-${USER_HOME}/.dsh}"
export DSH_TOOLS_MODE="${DSH_TOOLS_MODE:-both}"
export DSH_PERMISSION_MODE="${DSH_PERMISSION_MODE:-workspace-write}"
export DSH_TELEMETRY_DISABLED="${DSH_TELEMETRY_DISABLED:-1}"
export DOCKER_HOST="${DOCKER_HOST:-tcp://127.0.0.1:2376}"
export DOCKER_TLS_VERIFY="${DOCKER_TLS_VERIFY:-1}"
export DOCKER_CERT_PATH="${DOCKER_CERT_PATH:-/certs/client}"
EOF
chmod 0644 /etc/profile.d/dev-runtime.sh

if ! grep -q 'profile.d/dev-runtime.sh' /etc/zsh/zshenv 2>/dev/null; then
  printf '%s\n' '[ -r /etc/profile.d/dev-runtime.sh ] && . /etc/profile.d/dev-runtime.sh' >> /etc/zsh/zshenv
fi

/usr/sbin/sshd -D -e &
SSHD_PID=$!

cleanup() {
  kill -TERM "${SSHD_PID}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

if [ "${1:-}" = "dsh" ] && [ "${2:-}" = "web" ]; then
  set -- "$@" --trusted-host "${DSH_TRUSTED_HOST}"
fi

cd "${USER_HOME}/workspace"
exec gosu "${USERNAME}" "$@"
