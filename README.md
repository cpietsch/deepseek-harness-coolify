# DeepSeek Harness development environment for Coolify

A private, persistent development environment for DeepSeek Harness, adapted from
[`cpietsch/code-server-cpu`](https://github.com/cpietsch/code-server-cpu).

It provides:

- the published DeepSeek Harness Web UI on private Tailscale HTTPS;
- the [dsh-superagent prototype](https://github.com/deepseek-ai/dsh-superagent-prototype) panel on private Tailscale HTTPS port 8443;
- SSH access for VS Code/Cursor Remote SSH;
- Node.js 24 and the upstream-pinned pnpm 11.7.0;
- Git, GitHub CLI, Python, uv, build tools, ripgrep, tmux and zsh;
- a persistent source workspace and user home;
- a dedicated Docker-in-Docker daemon with mutual TLS;
- automatic discovery of each instance's full Tailscale MagicDNS authority;
- no host Docker socket and no public host ports;
- helpers for cloning, installing, type-checking and running Harness from source.

DeepSeek Harness is a developer preview. This repository pins the current
published npm `latest` release, `@deepseek-ai/dsh@0.2.1-rc.5`, instead of
silently taking breaking updates. The newer `0.2.2-alpha.2` dist-tag is not
used: the superagent prototype declares `engines.dsh` of `^0.2.1-alpha.2`,
which `0.2.1-rc.5` satisfies.

## Architecture

The Tailscale, DinD, Harness and superagent containers share one network
namespace. Harness keeps its Web UI on `127.0.0.1:3080`. The superagent profile
keeps its panel on `127.0.0.1:3082`. Tailscale Serve proxies private HTTPS on
443 to the Harness UI and on 8443 to the superagent panel. DinD listens with
mutual TLS on TCP port 2376 (the upstream image binds `0.0.0.0:2376` inside
that shared namespace) and has its own persistent image/container store. The
Coolify host Docker socket is never mounted. Clients in this stack still
connect through `127.0.0.1:2376`.

## Prerequisites

1. A Coolify VM with `/dev/net/tun` available.
2. A Tailscale auth key carrying `tag:ai`.
3. HTTPS certificates enabled for your tailnet.
4. Your SSH public key.

The Tailscale policy must define `tag:ai` and allow your normal devices to reach
it. This repository does not use Funnel and does not expose the service publicly.

## Deploy with Coolify

1. Push this directory to a Git repository.
2. In Coolify choose **New Resource → Docker Compose from Git**.
3. Select the repository and `docker-compose.yml`.
4. Do not assign a public Coolify domain.
5. Set the environment variables:

| Variable | Value |
|---|---|
| `TS_AUTHKEY` | Reusable, pre-approved Tailscale auth key tagged `tag:ai` |
| `SSH_AUTHORIZED_KEYS` | One or more SSH public keys, newline-separated |
| `TS_HOSTNAME` | Optional; defaults to `deepseek-harness`, but must be unique when running multiple instances |

`DSH_TRUSTED_HOST` is no longer required. The Harness entrypoint reads the
actual full MagicDNS name from the healthy Tailscale sidecar and passes it to
`dsh web --trusted-host`. You may still set a bare `host[:port]` value as an
override for Headscale or a custom proxy authority.

Optional provider variables are `DEEPSEEK_API_KEY`, `OPENAI_API_KEY`,
`ANTHROPIC_API_KEY`, and `DEEPSEEK_BASE_URL`. The DeepSeek URL defaults to
`https://api.deepseek.com`; set it only when using an OpenAI-compatible proxy.
Credentials may instead be saved through **Settings → Models**. Harness stores
UI-managed credentials under the persistent `DSH_HOME` volume. The operator Web
profile and the superagent profile keep separate credentials.

`DSH_TOOLS_MODE` is `native` or `ptc`. Leave it unset or `native` unless you want
the whole process in programmatic tool-calling mode. The 0.1 value `both` is
rejected by 0.2.1.

`DSH_VERSION` defaults to `0.2.1-rc.5`. `DSH_SUPERAGENT_REF` defaults to
`6337fc823ce20251c8de8085948165c81aaa701e`, the published prototype commit.
Leave `DSH_SUPERAGENT_AUTO_UPDATE` at `0` so a restart does not move that
checkout. Port 8443 in Tailscale Serve is fixed in `docker-compose.yml`; keep
`DSH_SUPERAGENT_HTTPS_PORT` at `8443` unless you change both.

Deploy the resource. The first DinD start can take a little longer while it
creates its CA and client certificates. The Tailscale Serve configuration is
embedded directly in `docker-compose.yml`; this is intentional because Coolify
Git deployments do not reliably retain relative host bind mounts.

### Run multiple instances

Clone the Coolify resource and give each clone a unique `TS_HOSTNAME`:

```text
deepseek-1
deepseek-2
deepseek-3
```

The reusable tagged auth key and SSH key may stay the same. Every clone obtains
its own persistent volumes, Tailscale identity, HTTPS certificate and trusted
MagicDNS authority automatically.

## Access

Web UI:

```text
https://deepseek-harness.example-tailnet.ts.net
```

Superagent panel:

```text
https://deepseek-harness.example-tailnet.ts.net:8443
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

## dsh-superagent

The `superagent` service runs
[deepseek-ai/dsh-superagent-prototype](https://github.com/deepseek-ai/dsh-superagent-prototype)
as its own DeepSeek Harness profile, copied from the Web template. It is a
research prototype, not a DeepSeek product. The image builds the pinned
checkout. On start, `setup-superagent` links that checkout into the persistent
profile and writes machine config only when `cordis.patch.yml` does not already
contain a `dsh-superagent` entry. It never runs
`--from-default-profile` against an existing profile.

The service listens before GitHub is configured. The log prints a launch URL
with a token. Open that URL, then choose **Superagent** in the sidebar.
Unauthenticated `GET /` returns `401` until then. The panel stays in setup-wait
until the GitHub source has a repository and an agent CLI.

This stack does not create a GitHub account or store a token. Finish that over
SSH, as a dedicated agent account, never your own:

```bash
gh-agent auth login
gh-agent api user --jq .login
```

`gh-agent` is `gh` with `GH_CONFIG_DIR=$HOME/.config/gh-agent`. Give that
account write access to the repository, then in the panel set:

- GitHub source repository, as `owner/name`
- GitHub CLI `/home/dev/.local/bin/gh-agent`
- the GitHub logins allowed to ask for work
- an execution prepare command that checks out a clone under `~/workspace`

A local clone on the `workspace` volume survives redeploys. Query setup from
either container:

```bash
curl -sS -H 'x-orchestrator-request: 1' \
  http://127.0.0.1:3082/orchestrator/api/state
```

`scripts/dsh-superagent status` only sees the process from inside the
superagent container. Prefer the API above, or that service's logs.

If the tailnet ACL names ports, allow TCP `8443` to `tag:ai`. A rule that
already allows all TCP to that tag needs no change.

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
| `tailscale-socket` | Local socket used at startup to discover this node's MagicDNS name |
| `ssh-host-keys` | Stable SSH server identity |

Redeploying does not remove these volumes. Deleting the Coolify resource and
its volumes does.

## Security notes

- Do not mount `/var/run/docker.sock`; that would give Harness control of the
  Coolify host.
- DinD needs `privileged: true`. It is isolated from the host daemon, but a
  privileged container still increases the VM's attack surface.
- The DinD TLS port is bound on `0.0.0.0:2376` inside the shared Tailscale
  network namespace, so it is reachable on the tailnet. Mutual TLS is required;
  do not disable `DOCKER_TLS_VERIFY` or share the `dind-certs` volume.
- Never expose port 3080 or 22 through a public Coolify domain or host mapping.
- Keep `AllowFunnel` disabled.
- The default Harness permission mode is `workspace-write`. Use more permissive
  modes only deliberately.
- Superagent workers use the bundle's `danger-full-access` presets as the
  `dev` user. They can use the isolated DinD daemon. They still cannot see the
  Coolify host Docker socket.
- Keep telemetry disabled unless you have reviewed exactly what will be sent.

## Troubleshooting

Check private HTTPS routing in the Tailscale service terminal:

```bash
tailscale serve status
```

It should show the instance's `https://<name>.<tailnet>.ts.net` authority
proxying `/` to `http://127.0.0.1:3080`, and port `8443` proxying `/` to
`http://127.0.0.1:3082`. If Tailscale reports that no Serve configuration
exists, confirm the deployed Compose contains the top-level
`configs: tailscale-serve:` block.

The Harness startup log should contain:

```text
Using trusted Harness authority: <name>.<tailnet>.ts.net
```

Unauthenticated `GET /` on the Web UI returns `401`. That is expected until you
open the launch URL printed by `dsh web`; the compose healthcheck treats
`200`, `401`, and `303` as healthy.

## Updating

Change `DSH_VERSION` in Coolify and redeploy. Because upstream warns about
breaking changes, review the DeepSeek Harness release and migration notes first.
This tree moved from `0.1.1-rc.2` to `0.2.1-rc.5`. If Coolify still has
`DSH_TOOLS_MODE=both`, change it to `native` or delete it before redeploying;
0.2.1 rejects `both` and the Web UI will not start. Persistent profiles usually
keep working. If the Web UI fails to boot after that jump, move
`~/.dsh/profiles/web` aside and let `dsh web` recreate it. UI-managed
credentials live under the persistent `DSH_HOME` volume, not only in that
profile directory; confirm they are still present before deleting anything.

To move the superagent bundle, set `DSH_SUPERAGENT_REF` to a commit the
prototype still builds with this `DSH_VERSION`, then redeploy. The running
service relinks the bundle when that ref or the `dsh` version changes. It does
not overwrite an existing superagent `cordis.patch.yml`. Back up
`~/.dsh/state/superagent/orchestrator.sqlite` before that redeploy. A database
written by a newer prototype cannot be opened by an older one.

Update a source checkout separately:

```bash
cd ~/workspace/deepseek-harness
git pull --ff-only
pnpm install
pnpm run typecheck
```
