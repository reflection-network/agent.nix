# agent.nix

Nix flake providing the agent configuration schema and `lib.mkAgent` builder. Not a standalone project — imported by capsules as a flake input.

## Stack

Pure Nix.

## What mkAgent does

Takes an agent config attrset, validates it, and returns per-system outputs:

- **`devShells.default`** — shell with `agent-info` command
- **`packages.docker`** — layered Docker image (non-root UID 1000)
- **`web`** — nginx config bundle (packages, startCmd, port 8080)

## Schema fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Agent display name |
| `system-prompt` | yes | System prompt text |
| `provider` | no | LLM provider (e.g. `claude-code`, `anthropic`) |
| `model` | no | Model identifier |
| `transports.telegram.enable` | no | Enable Telegram transport |
| `transports.telegram.allowed-users` | no | List of allowed Telegram usernames |
| `transports.telegram.mention-only` | no | Only respond when mentioned |

Validation is type-checked at Nix eval time with clear assertion messages.

## Docker image

- Non-root user `agent` (UID 1000, GID 1000)
- nginx listens on port 8080, serves static landing page at `/` and `/hello` endpoint
- Extension point: adapters add configs via `/etc/nginx/conf.d/*.conf`
- Includes: bash, coreutils, nginx, agent-info
- Creates `/home/agent`, `/tmp`, `/srv/www` with proper ownership
