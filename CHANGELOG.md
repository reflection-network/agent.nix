# Changelog

## Unreleased

- `enableOpencode` — opt-in OpenCode support (wrapper, setup tool, credential decryption)

## v0.1.0

Initial release.

### `mkAgent` options

- `name` — agent name, used as docker image name
- `repoUrl` — agent repo URL, baked into docker entrypoint
- `secretsFile` — path to sops-encrypted secrets file
- `enableClaude` — opt-in Claude Code support (wrapper, setup tool, credential decryption)
- `extraPackages` — optional function `pkgs -> [derivation]`

### Outputs

- `devShells.<system>.default` — dev shell with base tools + enabled agent tools + `extraPackages`
- `packages.<system>.docker` — production docker image + `extraPackages`
