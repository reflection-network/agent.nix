# agent.nix

Declarative schema and builder for AI agent capsules.

## What it does

agent.nix is a Nix flake that defines the configuration schema for Reflection agents and provides `lib.mkAgent` — a builder that validates config and produces runnable artifacts. Capsules import it as a flake input. Adapters extend it with runtime-specific backends.

## Usage

agent.nix is a library, not a standalone project. Use it from a capsule's `flake.nix`:

```nix
{
  inputs.agent-nix.url = "github:reflection-network/agent.nix";

  outputs = { self, agent-nix }:
    agent-nix.lib.mkAgent {
      agent = {
        name = "Ada";
        system-prompt = "You are Ada, a helpful assistant.";
      };
    };
}
```

### Required fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Agent's display name (used to derive Docker image name) |
| `system-prompt` | string | Behavioral instructions for the agent |

Both fields are validated at Nix eval time — missing or empty values fail the build with a clear error.

### Optional fields

These fields are used by adapters that support them. Adapters that don't recognize a field simply ignore it. All optional fields are validated when present — a field with a wrong type fails the build.

| Field | Type | Description |
|-------|------|-------------|
| `provider` | string | LLM provider identifier (e.g. `"anthropic"`, `"claude-code"`, `"openai"`) |
| `model` | string | Model identifier (e.g. `"claude-sonnet-4-5-20250929"`) |
| `transports.telegram.enable` | bool | Enable the Telegram channel |
| `transports.telegram.allowed-users` | list of strings | Telegram usernames allowed to interact with the bot |
| `transports.telegram.mention-only` | bool | Only respond when @mentioned in groups |

Example with optional fields:

```nix
agent = {
  name = "Ada";
  system-prompt = "You are Ada, a helpful assistant.";
  provider = "claude-code";
  model = "claude-sonnet-4-5-20250929";
  transports.telegram.enable = true;
  transports.telegram.allowed-users = [ "alice" "bob" ];
  transports.telegram.mention-only = true;
};
```

A capsule with just `name` and `system-prompt` is still valid. Optional fields only matter when using an adapter that supports them (e.g. adapter-zeroclaw uses `provider` and `transports`; adapter-claude ignores them).

### Outputs

`mkAgent` produces per-system outputs:

- **`devShells.default`** — shell with `agent-info` command that prints agent name and system prompt
- **`packages.docker`** — layered Docker image (non-root, UID 1000) with the agent identity baked in
- **`web`** — nginx web server config for adapters (see below)

```bash
# Enter dev shell
nix develop

# Build Docker image
nix build .#docker
docker load < result
```

### Web server

Every agent gets an nginx instance listening on port 8080. The base image serves a static landing page at `/` showing the agent's name and status. Adapters extend this with runtime-specific proxy rules.

The `web` output provides everything adapters need:

```nix
web = {
  packages = [ pkgs.nginx webRoot nginxConfigDir ];
  startCmd = "${pkgs.nginx}/bin/nginx -c /etc/nginx/nginx.conf";
  port = 8080;
};
```

| Field | Description |
|-------|-------------|
| `web.packages` | Nix packages to include in the Docker image (nginx binary, static files, config) |
| `web.startCmd` | Shell command to start nginx (call in entrypoint before the main process) |
| `web.port` | Port nginx listens on (use for Docker `ExposedPorts`) |

The nginx config includes `include /etc/nginx/conf.d/*.conf;` inside the server block. Adapters that need to proxy additional services drop a `.conf` file into `/etc/nginx/conf.d/`. The base creates the directory; the adapter populates it.

## How adapters extend it

Adapters wrap `mkAgent` to add runtime capabilities while keeping the same interface:

```nix
# Capsule switches from agent-nix to an adapter — same config, different backend
inputs.adapter-claude.url = "github:reflection-network/adapter-claude";
# or
inputs.adapter-zeroclaw.url = "github:reflection-network/adapter-zeroclaw";
```

The adapter calls `agent-nix.lib.mkAgent` internally for validation, then builds a richer Docker image with the adapter's runtime. Adapters include `web.packages` in Docker contents, call `web.startCmd` in their entrypoint, and can drop proxy configs into `/etc/nginx/conf.d/`. Available adapters:

| Adapter | Backend | Transport |
|---------|---------|-----------|
| [adapter-claude](https://github.com/reflection-network/adapter-claude) | Claude Code CLI | Telegram (bash long-poll) |
| [adapter-zeroclaw](https://github.com/reflection-network/adapter-zeroclaw) | ZeroClaw (Rust binary) | Telegram (native channel) |

## Documentation

- [Getting started](https://docs.reflection.network/getting-started) — create your first capsule
- [Building containers](https://docs.reflection.network/building-containers) — how Docker images are built
- [Adapters](https://docs.reflection.network/adapters) — adding a runtime backend
