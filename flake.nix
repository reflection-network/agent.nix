{
  description = "Reflection agent.nix — declarative agent schema";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    {
      lib.mkAgent = { agent }:
        flake-utils.lib.eachDefaultSystem (system:
          let
            pkgs = nixpkgs.legacyPackages.${system};

            cfg = agent;

            # Helper: check optional field type
            optString = field: !(cfg ? ${field}) || (builtins.isString cfg.${field} && cfg.${field} != "");
            optBool = path:
              let
                val = builtins.foldl' (acc: k: if acc != null && acc ? ${k} then acc.${k} else null) cfg path;
              in
              val == null || builtins.isBool val;
            optListOfStrings = path:
              let
                val = builtins.foldl' (acc: k: if acc != null && acc ? ${k} then acc.${k} else null) cfg path;
              in
              val == null || (builtins.isList val && builtins.all builtins.isString val);

            assertions = [
              # required
              {
                assertion = cfg ? name && builtins.isString cfg.name && cfg.name != "";
                message = "agent.name must be a non-empty string";
              }
              {
                assertion = cfg ? system-prompt && builtins.isString cfg.system-prompt && cfg.system-prompt != "";
                message = "agent.system-prompt must be a non-empty string";
              }
              # optional: provider / model
              {
                assertion = optString "provider";
                message = "agent.provider must be a non-empty string when specified";
              }
              {
                assertion = optString "model";
                message = "agent.model must be a non-empty string when specified";
              }
              # optional: transports.telegram
              {
                assertion = optBool [ "transports" "telegram" "enable" ];
                message = "agent.transports.telegram.enable must be a boolean when specified";
              }
              {
                assertion = optListOfStrings [ "transports" "telegram" "allowed-users" ];
                message = "agent.transports.telegram.allowed-users must be a list of strings when specified";
              }
              {
                assertion = optBool [ "transports" "telegram" "mention-only" ];
                message = "agent.transports.telegram.mention-only must be a boolean when specified";
              }
            ];

            failedAssertions = builtins.filter (a: !a.assertion) assertions;

            assertionCheck =
              if failedAssertions != [] then
                throw (builtins.concatStringsSep "\n" (map (a: "assertion failed: ${a.message}") failedAssertions))
              else
                true;

            escPrompt = builtins.replaceStrings [''"'' "$"] [''\"'' "\\$"] cfg.system-prompt;

            agent-info = pkgs.writeShellScriptBin "agent-info" ''
              echo "name: ${cfg.name}"
              ${if cfg ? provider then ''echo "provider: ${cfg.provider}"'' else ""}
              ${if cfg ? model then ''echo "model: ${cfg.model}"'' else ""}
              echo ""
              echo "system prompt:"
              echo "${escPrompt}"
            '';

            etcFiles = pkgs.runCommand "etc-files" {} ''
              mkdir -p $out/etc
              echo "root:x:0:0:root:/root:/bin/sh" > $out/etc/passwd
              echo "agent:x:1000:1000:Agent:/home/agent:/bin/bash" >> $out/etc/passwd
              echo "root:x:0:" > $out/etc/group
              echo "agent:x:1000:" >> $out/etc/group
            '';

            imageName = builtins.replaceStrings [ " " ] [ "-" ]
              (pkgs.lib.toLower cfg.name);
          in
          assert assertionCheck;
          {
            devShells.default = pkgs.mkShell {
              packages = [ agent-info ];
              shellHook = ''
                echo ""
                echo "  reflection: ${cfg.name}"
                echo ""
              '';
            };

            packages.docker = pkgs.dockerTools.buildLayeredImage {
              name = imageName;
              tag = "latest";
              contents = [ pkgs.bash pkgs.coreutils agent-info etcFiles ];
              fakeRootCommands = ''
                mkdir -p home/agent tmp
                chmod 1777 tmp
                chown -R 1000:1000 home/agent
              '';
              config = {
                User = "1000:1000";
                Env = [ "HOME=/home/agent" ];
                WorkingDir = "/home/agent";
                Entrypoint = [ "${agent-info}/bin/agent-info" ];
              };
            };
          }
        );
    };
}
