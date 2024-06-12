{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?rev=ff0dbd94265ac470dda06a657d5fe49de93b4599";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";
    services-flake.url = "github:juspay/services-flake";
  };
  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = import inputs.systems;
      imports = [
        inputs.process-compose-flake.flakeModule
      ];
      perSystem = {
        self',
        pkgs,
        ...
      }: {
        process-compose."default" = {config, ...}: let
          tempo = config.services.tempo.tempo;
          tempoHostPort = "${tempo.httpAddress}:${builtins.toString tempo.httpPort}";
          prometheus = config.services.prometheus.prometheus;
          prometheusUrl = "http://${prometheus.listenAddress}:${builtins.toString prometheus.port}";
        in {
          imports = [
            inputs.services-flake.processComposeModules.default
          ];

          services.tempo.tempo.enable = true;
          services.grafana.grafana = {
            enable = true;
            http_port = 4000;
            extraConf."auth.anonymous" = {
              enabled = true;
              org_role = "Admin";
            };


            datasources = [
              {
                name = "Tempo";
                type = "tempo";
                access = "proxy";
                url = "http://${tempoHostPort}";
              }
              {
                access = "proxy";
                basicAuth = false;
                editable = false;
                isDefault = false;
                jsonData = {httpMethod = "GET";};
                name = "Prometheus";
                orgId = 1;
                type = "prometheus";
                uid = "prometheus";
                url = prometheusUrl;
                version = 1;
              }
              # {
              #   access = "proxy";
              #   apiVersion = 1;
              #   basicAuth = false;
              #   editable = false;
              #   isDefault = true;
              #   jsonData = {
              #     httpMethod = "GET";
              #     serviceMap = {datasourceUid = "prometheus";};
              #   };
              #   name = "Tempo";
              #   orgId = 1;
              #   type = "tempo";
              #   uid = "tempo";
              #   url = "http://tempo:3200";
              #   version = 1;
              # }
            ];
          };
          services.prometheus.prometheus = {
            enable = false;
            extraConfig = {
              global = {
                evaluation_interval = "15s";
                scrape_interval = "15s";
              };
              scrape_configs = [
                {
                  job_name = "prometheus";
                  static_configs = [{targets = ["localhost:9090"];}];
                }
                {
                  job_name = "tempo";
                  static_configs = [{targets = [tempoHostPort];}];
                }
              ];
            };
          };
          # settings.processes.tsx = {
          #   command = "tsx --watch src/main.ts";
          # };
        };

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            alejandra
          ];
        };
      };
    };
}