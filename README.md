# agent.nix

Reusable Nix flake for autonomous agent infrastructure. Provides `lib.mkAgent` — a function that takes agent-specific config and returns flake outputs with `devShell` and `docker`.

## Usage

```nix
{
  inputs.agent-nix.url = "github:ref/agent.nix/v0.1.0";

  outputs = { self, agent-nix }:
    agent-nix.lib.mkAgent {
      name = "my-agent";
      repoUrl = "https://github.com/org/my-agent";
      secretsFile = ./secrets.yaml;
      enableClaude = true;
    };
}
```

## Options

| Option | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | string | yes | — | Agent name. Used as docker image name. |
| `repoUrl` | string | yes | — | URL of the agent's repo. Baked into docker entrypoint. |
| `secretsFile` | path | yes | — | Path to sops-encrypted secrets file. Baked into docker image at `/app/secrets.yaml`. |
| `enableClaude` | bool | no | `false` | Include Claude Code CLI, credential wrapper, and `claude-setup` dev tool. |
| `extraPackages` | function | no | `_: []` | Function `pkgs -> [derivation]`. Additional packages added to both devShell and docker image. |

## Outputs

Per system:

- `devShells.<system>.default` — development shell with base tools + enabled agent tools + `extraPackages`
- `packages.<system>.docker` — production docker image with full package set + `extraPackages`

## Base packages

Always included:

- **devShell**: `git`, `sops`, `age`, `jq`
- **docker**: `bash`, `coreutils`, `git`, `curl`, `age`, `sops`, `cacert`, `jq`

## enableClaude

When `true`, adds:

- **devShell**: `claude-code`, `claude-setup` (interactive login tool that saves encrypted credentials)
- **docker**: `claude` wrapper that auto-encrypts and pushes credential updates after token refresh
- **entrypoint**: decrypts `claude-credentials.yaml` from the repo into `~/.claude/.credentials.json`

## Docker image

Self-contained production image. Entrypoint:

1. Decrypts `/app/secrets.yaml` (expects `GITHUB_TOKEN`)
2. Clones the agent's repo into `$HOME`
3. Decrypts tool-specific credentials (if enabled)
4. Drops into bash

## secrets.yaml

The sops-encrypted secrets file must contain at minimum:

```yaml
GITHUB_TOKEN: ghp_...
```
