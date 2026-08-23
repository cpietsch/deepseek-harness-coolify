# DeepSeek Harness development environment for Coolify

A private, persistent development environment for DeepSeek Harness, adapted from
[`cpietsch/code-server-cpu`](https://github.com/cpietsch/code-server-cpu).

It provides:

- the published DeepSeek Harness Web UI on private Tailscale HTTPS;
- SSH access for VS Code/Cursor Remote SSH;
- Node.js 24 and the upstream-pinned pnpm 11.7.0;
- Git, GitHub CLI, Python, uv, build tools, ripgrep, tmux and zsh;
- a persistent source workspace and user home;
- a dedicated Docker-in-Docker daemon with mutual TLS;
- no host Docker socket and no public host ports;
- helpers for cloning, installing, type-checking and running Harness from source.

DeepSeek Harness is a developer preview. This repository pins the current
published release instead of silently taking breaking updates.

## Architecture

The Tailscale, DinD and Harness containers share one network namespace. Harness
keeps its Web UI on `127.0.0.1:3080`; Tailscale Serve proxies private HTTPS to
that loopback address. DinD listens with mutual TLS on `127.0.0.1:2376` and has
its own persistent image/container store. The Coolify host Docker socket is
never mounted.

## Prerequisites

1. A Coolify VM with `/dev/net/tun` available.
2. A Tailscale auth key carrying `tag:ai`.
3. HTTPS certificates enabled for your tailnet.
4. Your SSH public key.
5. The full MagicDNS hostname you want to use, for example
   `deepseek-harness.example-tailnet.ts.net`.

The Tailscale policy must define `tag:ai` and allow your normal devices to reach
it. This repository does not use Funnel and does not expose the service publicly.

## Deploy with Coolify

1. Push this directory to a Git repository.
2. In Coolify choose **New Resource → Docker Compose from Git**.
3. Select the repository and `docker-compose.yml`.
4. Do not assign a public Coolify domain.
5. Set the required environment variables:

| Variable | Value |
|---|---|
| `TS_AUTHKEY` | Reusable, pre-approved Tailscale auth key tagged `tag:ai` |
| `TS_HOSTNAME` | `deepseek-harness` |
| `DSH_TRUSTED_HOST` | Full MagicDNS name, without `https://` |
| `SSH_AUTHORIZED_KEYS` | One or more SSH public keys, newline-separated |

Optional provider variables are `DEEPSEEK_API_KEY`, `OPENAI_API_KEY`,
`ANTHROPIC_API_KEY`, and `DEEPSEEK_BASE_URL`. Credentials may instead be saved
through **Settings → Models**. Harness stores UI-managed credentials under the
persistent `DSH_HOME` volume.

Deploy the resource. The first DinD start can take a little longer while it
creates its CA and client certificates.

## Access

Web UI:

```text
https://deepseek-harness.example-tailnet.ts.net
```

SSH:

```bash
ssh dev@deepseek-harness
```

Suggested local SSH configuration:

```ssh-config
Host deepseek-harness
    HostName deepseek-harness.example-tailnet.ts.net
    User dev
    ForwardAgent yes
    ServerAliveInterval 30
```

Connect VS Code or Cursor with **Remote-SSH: Connect to Host** and select
`deepseek-harness`.

## Verify the environment

After connecting with SSH:

```bash
dsh --version
node --version
pnpm --version
docker info
docker run --rm hello-world
```

`docker info` must describe the isolated DinD daemon. Containers and images
created there are deliberately invisible to Coolify.

## Develop DeepSeek Harness from source

Prepare the checkout once:

```bash
setup-harness-source
```

The helper clones into `~/workspace/deepseek-harness`, runs `pnpm install`, and
runs the upstream `pnpm run typecheck` setup check.

Daily commands:

```bash
cd ~/workspace/deepseek-harness
pnpm run build
pnpm test
pnpm run lint
pnpm run check:all
```

The installed Web UI continues running on port 3080. To preview the source
checkout independently, forward source port 3081 from your laptop:

```bash
ssh -L 3081:127.0.0.1:3081 dev@deepseek-harness
```

Then, in that SSH session:

```bash
cd ~/workspace/deepseek-harness
pnpm run build
dsh-source-web
```

Open `http://127.0.0.1:3081` on the laptop. This keeps the development instance
off the tailnet and avoids a port collision with the packaged instance.

For frontend watch mode, use the upstream command after an initial build:

```bash
pnpm run dev:web
```

## Harness plugins and subagents

The image supports normal profile plugin management:

```bash
dsh plugin --profile web add <package-or-git-spec>
dsh plugin --profile web update
```

Optional Codex and Claude Code provider bundles can be installed into the
persistent Web profile:

```bash
dsh plugin --profile web add \
  @deepseek-ai/dsh-subagent-codex \
  @deepseek-ai/dsh-subagent-claude-code
```

Redeploy or restart the Harness service after changing bundle membership. The
bundles register dormant providers; exposing their tools to an agent still
requires enabling the matching rows in a copied Harness preset. Their native
authentication and settings remain authoritative.

## Persistence

| Volume | Purpose |
|---|---|
| `dev-home` | Shell state, Harness settings, credentials and profiles |
| `workspace` | Source repositories and project files |
| `dind-data` | DinD images, containers and Docker volumes |
| `dind-certs` | DinD CA and mutual-TLS client certificates |
| `tailscale-state` | Stable Tailscale node identity |
| `ssh-host-keys` | Stable SSH server identity |

Redeploying does not remove these volumes. Deleting the Coolify resource and
its volumes does.

## Security notes

- Do not mount `/var/run/docker.sock`; that would give Harness control of the
  Coolify host.
- DinD needs `privileged: true`. It is isolated from the host daemon, but a
  privileged container still increases the VM's attack surface.
- Never expose port 3080 or 22 through a public Coolify domain or host mapping.
- Keep `AllowFunnel` disabled.
- The default Harness permission mode is `workspace-write`. Use more permissive
  modes only deliberately.
- Keep telemetry disabled unless you have reviewed exactly what will be sent.

## Updating

Change `DSH_VERSION` in Coolify and redeploy. Because upstream warns about
breaking changes, review the DeepSeek Harness release and migration notes first.

Update a source checkout separately:

```bash
cd ~/workspace/deepseek-harness
git pull --ff-only
pnpm install
pnpm run typecheck
```
