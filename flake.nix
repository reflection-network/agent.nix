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

            assertions = [
              {
                assertion = cfg ? name && builtins.isString cfg.name && cfg.name != "";
                message = "agent.name must be a non-empty string";
              }
              {
                assertion = cfg ? system-prompt && builtins.isString cfg.system-prompt && cfg.system-prompt != "";
                message = "agent.system-prompt must be a non-empty string";
              }
            ];

            failedAssertions = builtins.filter (a: !a.assertion) assertions;

            assertionCheck =
              if failedAssertions != [] then
                throw (builtins.concatStringsSep "\n" (map (a: "assertion failed: ${a.message}") failedAssertions))
              else
                true;

            agent-info = pkgs.writeShellScriptBin "agent-info" ''
              echo "name: ${cfg.name}"
              echo ""
              echo "system prompt:"
              echo "${builtins.replaceStrings [''"'' "$"] [''\"'' "\\$"] cfg.system-prompt}"
            '';
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
          }
        );
    };
}
