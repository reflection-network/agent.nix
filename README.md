# agent.nix

Reusable Nix flake for Claude agent infrastructure. Provides `lib.mkAgent` — a function that takes agent-specific config and returns flake outputs with `devShell` and `docker`.

## Usage

```nix
{
  inputs.agent-nix.url = "github:ref/agent.nix/v0.1.0";

  outputs = { self, agent-nix }:
    agent-nix.lib.mkAgent {
      name = "my-agent";
      repoUrl = "https://github.com/org/my-agent";
      secretsFile = ./secrets.yaml;
    };
}
```

## Options

| Option | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | string | yes | — | Agent name. Used as docker image name. |
| `repoUrl` | string | yes | — | URL of the agent's home repo. Baked into docker entrypoint. |
| `secretsFile` | path | yes | — | Path to sops-encrypted secrets file. Baked into docker image at `/app/secrets.yaml`. |
| `extraPackages` | function | no | `_: []` | Function `pkgs -> [derivation]`. Additional packages added to both devShell and docker image. |

## Outputs

Per system:

- `devShells.<system>.default` — development shell with `git sops age jq claude-setup` + `extraPackages`
- `packages.<system>.docker` — docker image with full production set including `claude` wrapper + `extraPackages`

## devShell

Contains tools for agent repo development:

- `git`, `sops`, `age`, `jq` — for managing secrets and config
- `claude-code` — Claude CLI
- `claude-setup` — interactive tool that runs `claude login` and saves encrypted credentials to `claude-credentials.yaml`

## Docker image

Self-contained production image. Entrypoint:

1. Decrypts `/app/secrets.yaml` (expects `GITHUB_TOKEN`)
2. Clones the agent's home repo into `$HOME`
3. Decrypts Claude credentials from `claude-credentials.yaml` in the repo
4. Drops into bash

The `claude` binary is a wrapper that auto-encrypts and pushes credential updates back to the repo after token refresh.

## secrets.yaml

The sops-encrypted secrets file must contain at minimum:

```yaml
GITHUB_TOKEN: ghp_...
```
