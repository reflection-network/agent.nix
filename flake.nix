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

            nginxConf = pkgs.writeText "nginx.conf" ''
              worker_processes 1;
              pid /tmp/nginx.pid;
              error_log /tmp/nginx-error.log warn;

              events {
                worker_connections 64;
              }

              http {
                include ${pkgs.nginx}/conf/mime.types;
                default_type application/octet-stream;
                access_log /tmp/nginx-access.log;

                client_body_temp_path /tmp/nginx-client-body;
                proxy_temp_path /tmp/nginx-proxy;
                fastcgi_temp_path /tmp/nginx-fastcgi;
                uwsgi_temp_path /tmp/nginx-uwsgi;
                scgi_temp_path /tmp/nginx-scgi;

                server {
                  listen 8080;
                  root /srv/www;
                  index index.html;

                  location = /hello {
                    default_type text/plain;
                    return 200 "hello from ${cfg.name}\n";
                  }

                  include /etc/nginx/conf.d/*.conf;
                }
              }
            '';

            indexHtml = pkgs.writeText "index.html" ''
              <!DOCTYPE html>
              <html lang="en">
              <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <title>${cfg.name}</title>
                <style>
                  body { font-family: system-ui, sans-serif; max-width: 600px; margin: 80px auto; padding: 0 20px; color: #333; }
                  h1 { margin-bottom: 4px; }
                  .label { color: #888; font-size: 14px; }
                  ul { list-style: none; padding: 0; }
                  li { padding: 4px 0; }
                </style>
              </head>
              <body>
                <h1>${cfg.name}</h1>
                <p class="label">Reflection agent</p>
                <hr>
                <h2>Services</h2>
                <ul>
                  <li>Web — active</li>
                </ul>
              </body>
              </html>
            '';

            webRoot = pkgs.runCommand "web-root" {} ''
              mkdir -p $out/srv/www
              cp ${indexHtml} $out/srv/www/index.html
            '';

            nginxConfigDir = pkgs.runCommand "nginx-config-dir" {} ''
              mkdir -p $out/etc/nginx/conf.d
              cp ${nginxConf} $out/etc/nginx/nginx.conf
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
              contents = [ pkgs.bash pkgs.coreutils agent-info etcFiles pkgs.nginx webRoot nginxConfigDir ];
              fakeRootCommands = ''
                mkdir -p home/agent tmp srv/www
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

            web = {
              packages = [ pkgs.nginx webRoot nginxConfigDir ];
              startCmd = "${pkgs.nginx}/bin/nginx -c /etc/nginx/nginx.conf";
              port = 8080;
            };
          }
        );
    };
}
