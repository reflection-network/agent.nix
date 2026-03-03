# Changelog

## v0.1.0

Initial release.

### `mkAgent` options

- `name` — agent name, used as docker image name
- `repoUrl` — agent repo URL, baked into docker entrypoint
- `secretsFile` — path to sops-encrypted secrets file
- `extraPackages` — optional function `pkgs -> [derivation]`

### Outputs

- `devShells.<system>.default` — dev shell with `git sops age jq claude-code claude-setup` + `extraPackages`
- `packages.<system>.docker` — production docker image with `claude` credential wrapper + `extraPackages`
