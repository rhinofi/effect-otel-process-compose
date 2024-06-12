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

          services.tempo.tempo = {
            enable = true;
            extraConfig = {
              compactor = {
                compaction = { block_retention = "1h"; };
              };
              ingester = {max_block_duration = "5m";};
              metrics_generator = {
                registry = {
                  external_labels = {
                    source = "tempo";
                  };
                };
                storage = {
                  path = "/tmp/tempo/generator/wal";
                  remote_write = [
                    {
                      send_exemplars = true;
                      url = "${prometheusUrl}/api/v1/write";
                    }
                  ];
                };
              };
              overrides = {defaults = {metrics_generator = {processors = ["service-graphs" "span-metrics"];};};};
              query_frontend = {
                search = {
                  duration_slo = "5s";
                  throughput_bytes_slo = 1073741824;
                };
                trace_by_id = {duration_slo = "5s";};
              };
            };
          };
          services.grafana.grafana = {
            enable = true;
            http_port = 4000;
            extraConf = {
              "auth.anonymous" = {
                enabled = true;
                org_role = "Admin";
              };
              feature_toggles = {
                enable = "traceqlEditor";
              };
            };

            datasources = [
              {
                name = "Tempo";
                type = "tempo";
                uid = "tempo";
                access = "proxy";
                url = "http://${tempoHostPort}";
                jsonData = {
                  httpMethod = "GET";
                  serviceMap.datasourceUid = "prometheus";
                };
                orgId = 1;
              }
              {
                access = "proxy";
                basicAuth = false;
                editable = false;
                isDefault = false;
                jsonData = {
                  httpMethod = "GET";
                };
                name = "Prometheus";
                orgId = 1;
                type = "prometheus";
                uid = "prometheus";
                url = prometheusUrl;
                version = 1;
              }
            ];
          };
          services.prometheus.prometheus = {
            enable = true;
            extraFlags = [
              "--web.enable-remote-write-receiver"
              "--enable-feature=exemplar-storage"
            ];
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
        };

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            alejandra
          ];
        };
      };
    };
}