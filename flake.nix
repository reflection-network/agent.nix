{
  description = "Reusable agent infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    {
      lib.mkAgent = {
        name,
        repoUrl,
        secretsFile,
        extraPackages ? _: [],
      }:
        flake-utils.lib.eachDefaultSystem (system:
          let
            pkgs = import nixpkgs {
              inherit system;
              config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [
                "claude-code"
              ];
            };

            # Wrapper that refreshes Claude credentials in secrets.yaml after token refresh
            claudeWrapper = pkgs.writeShellScriptBin "claude" ''
              CREDS_FILE="$HOME/.claude/.credentials.json"
              SECRETS_FILE="$HOME/secrets.yaml"

              BEFORE=$(sha256sum "$CREDS_FILE" 2>/dev/null | cut -d' ' -f1)

              ${pkgs.claude-code}/bin/claude "$@"
              EXIT_CODE=$?

              AFTER=$(sha256sum "$CREDS_FILE" 2>/dev/null | cut -d' ' -f1)

              CREDS_ENCRYPTED="$HOME/claude-credentials.yaml"
              if [ "$BEFORE" != "$AFTER" ] && [ -f "$CREDS_ENCRYPTED" ]; then
                CREDS=$(${pkgs.jq}/bin/jq -c . "$CREDS_FILE")
                echo "CLAUDE_CREDENTIALS: '$CREDS'" > "$CREDS_ENCRYPTED"
                ${pkgs.sops}/bin/sops -e -i "$CREDS_ENCRYPTED"
                git -C "$HOME" add claude-credentials.yaml
                git -C "$HOME" commit -m "chore: refresh Claude credentials"
                git -C "$HOME" push
              fi

              exit $EXIT_CODE
            '';

            # Dev tool: run claude login in temp home, save credentials to claude-credentials.yaml
            claudeSetup = pkgs.writeShellScriptBin "claude-setup" ''
              TMPHOME=$(mktemp -d)
              trap "rm -rf $TMPHOME" EXIT

              echo "Running claude login with temporary home..."
              HOME=$TMPHOME ${pkgs.claude-code}/bin/claude login

              CREDS_FILE="$TMPHOME/.claude/.credentials.json"
              if [ ! -f "$CREDS_FILE" ]; then
                echo "Error: credentials file not found after login"
                exit 1
              fi

              CREDS=$(${pkgs.jq}/bin/jq -c . "$CREDS_FILE")
              echo "CLAUDE_CREDENTIALS: '$CREDS'" > claude-credentials.yaml
              ${pkgs.sops}/bin/sops -e -i claude-credentials.yaml

              echo "Claude credentials saved to claude-credentials.yaml"
            '';

            # Dev packages
            devPackages = with pkgs; [ git sops age jq claude-code ];

            # Production packages (full set for docker)
            prodPackages = with pkgs; [
              bash
              coreutils
              git
              curl
              age
              sops
              cacert
              jq
              claudeWrapper
            ];

            # Docker entrypoint: decrypt secrets -> setup home from repo -> bash
            dockerEntrypoint = pkgs.writeShellScript "entrypoint" ''
              set -e

              REPO_URL="${repoUrl}"

              export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
              export GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

              # Decrypt secrets into environment
              eval $(${pkgs.sops}/bin/sops -d --output-type dotenv /app/secrets.yaml)

              echo "machine github.com login x-access-token password $GITHUB_TOKEN" > "$HOME/.netrc"
              chmod 600 "$HOME/.netrc"

              git config --global safe.directory "$HOME"
              git config --global init.defaultBranch main
              git -C "$HOME" init
              git -C "$HOME" remote add origin "$REPO_URL"
              git -C "$HOME" fetch origin
              git -C "$HOME" checkout -f main

              # Decrypt Claude credentials from repo
              if [ -f "$HOME/claude-credentials.yaml" ]; then
                mkdir -p "$HOME/.claude"
                ${pkgs.sops}/bin/sops -d --extract '["CLAUDE_CREDENTIALS"]' "$HOME/claude-credentials.yaml" \
                  > "$HOME/.claude/.credentials.json"
                chmod 600 "$HOME/.claude/.credentials.json"
              fi

              exec ${pkgs.bash}/bin/bash
            '';

            extra = extraPackages pkgs;
          in
          {
            devShells.default = pkgs.mkShell {
              packages = devPackages ++ [ claudeSetup ] ++ extra;
            };

            packages.docker = pkgs.dockerTools.buildImage {
              name = name;
              tag = "latest";
              copyToRoot = [
                (pkgs.buildEnv {
                  name = "root";
                  paths = prodPackages ++ extra;
                  pathsToLink = [ "/bin" ];
                })
              ];
              extraCommands = ''
                mkdir -p home/agent app etc

                echo "root:x:0:0:root:/root:/bin/sh" > etc/passwd
                echo "agent:x:1000:1000:Agent:/home/agent:/bin/bash" >> etc/passwd
                echo "root:x:0:" > etc/group
                echo "agent:x:1000:" >> etc/group

                cp ${secretsFile} app/secrets.yaml
                chmod 444 app/secrets.yaml
                chmod 777 home/agent
              '';
              config = {
                User = "1000:1000";
                Env = [ "HOME=/home/agent" ];
                WorkingDir = "/home/agent";
                Cmd = [ "${dockerEntrypoint}" ];
              };
            };
          });
    };
}
