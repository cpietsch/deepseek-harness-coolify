FROM node:24-bookworm-slim

ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000
ARG DSH_VERSION=0.2.1-rc.5
ARG PNPM_VERSION=11.7.0

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=Europe/Berlin \
    DSH_HOME=/home/dev/.dsh \
    DSH_TELEMETRY_DISABLED=1 \
    DSH_TOOLS_MODE=native \
    COREPACK_HOME=/opt/corepack \
    COREPACK_DEFAULT_TO_LATEST=0

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash bubblewrap build-essential ca-certificates curl dnsutils \
        fd-find git git-lfs gnupg gosu htop iputils-ping jq less locales \
        nano net-tools openssh-client openssh-server pkg-config procps \
        python3 python3-dev python3-pip python3-venv ripgrep sudo tini \
        tmux tzdata unzip vim wget zip zsh \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && if npm install --help 2>&1 | grep -q -- '--dangerously-allow-all-scripts'; then \
         npm install --global --dangerously-allow-all-scripts "corepack@latest" "@deepseek-ai/dsh@${DSH_VERSION}"; \
       else \
         npm install --global "corepack@latest" "@deepseek-ai/dsh@${DSH_VERSION}"; \
       fi \
    && mkdir -p /opt/corepack \
    && corepack enable \
    && corepack prepare "pnpm@${PNPM_VERSION}" --activate \
    && chmod -R a+rX /opt/corepack \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        docker-ce-cli docker-buildx-plugin docker-compose-plugin gh \
    && curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh \
    && rm -rf /var/lib/apt/lists/*

# The official Node image already owns UID/GID 1000 as "node". Reuse it safely.
RUN set -eux; \
    current_user="$(getent passwd "${USER_UID}" | cut -d: -f1 || true)"; \
    current_group="$(getent group "${USER_GID}" | cut -d: -f1 || true)"; \
    if [ -n "${current_user}" ] && [ "${current_user}" != "${USERNAME}" ]; then usermod -l "${USERNAME}" "${current_user}"; fi; \
    if [ -n "${current_group}" ] && [ "${current_group}" != "${USERNAME}" ]; then groupmod -n "${USERNAME}" "${current_group}"; fi; \
    usermod -d "/home/${USERNAME}" -m -s /bin/zsh "${USERNAME}"; \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}"; \
    chmod 0440 "/etc/sudoers.d/${USERNAME}"; \
    mkdir -p "/home/${USERNAME}/.ssh" "/home/${USERNAME}/.dsh" "/home/${USERNAME}/workspace" /run/sshd /etc/ssh/hostkeys; \
    chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}"

# Pinned checkout of dsh-superagent-prototype. Declared here so changing the
# ref does not rebuild the apt/dsh layers above.
ARG DSH_SUPERAGENT_REPOSITORY=https://github.com/deepseek-ai/dsh-superagent-prototype.git
ARG DSH_SUPERAGENT_REF=6337fc823ce20251c8de8085948165c81aaa701e
ENV DSH_SUPERAGENT_DIR=/opt/dsh-superagent-prototype \
    DSH_SUPERAGENT_REF=${DSH_SUPERAGENT_REF}
RUN set -eux; \
    git clone "${DSH_SUPERAGENT_REPOSITORY}" /opt/dsh-superagent-prototype; \
    git -C /opt/dsh-superagent-prototype checkout --detach "${DSH_SUPERAGENT_REF}"; \
    cd /opt/dsh-superagent-prototype; \
    pnpm install --frozen-lockfile; \
    pnpm build; \
    chown -R "${USERNAME}:${USERNAME}" /opt/dsh-superagent-prototype

COPY sshd_dev.conf /etc/ssh/sshd_config.d/10-dev.conf
# Drop image-baked HostKey files and the package defaults so sshd only uses the
# volume-backed keys under /etc/ssh/hostkeys. Otherwise a rebuild rotates the
# identity clients already cached.
RUN sed -i -E 's/^HostKey /# HostKey /' /etc/ssh/sshd_config \
    && rm -f /etc/ssh/ssh_host_*
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/setup-harness-source.sh /usr/local/bin/setup-harness-source
COPY scripts/dsh-source-web.sh /usr/local/bin/dsh-source-web
COPY scripts/setup-superagent.sh /usr/local/bin/setup-superagent
COPY scripts/serve-superagent.sh /usr/local/bin/serve-superagent
RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/setup-harness-source \
    /usr/local/bin/dsh-source-web /usr/local/bin/setup-superagent /usr/local/bin/serve-superagent

WORKDIR /home/dev/workspace
EXPOSE 22 3080 3082

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["dsh", "web", "--no-open", "--port", "3080"]
