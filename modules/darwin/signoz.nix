# SigNoz observability platform via Podman Compose on nix-darwin
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.services.signoz;

  signozSrc = pkgs.fetchFromGitHub {
    owner = "SigNoz";
    repo = "signoz";
    tag = "v${cfg.version}";
    hash = cfg.srcHash;
  };

  clickhouseConfDir = "${signozSrc}/deploy/common/clickhouse";
  otelCollectorConfig = "${signozSrc}/deploy/docker/otel-collector-config.yaml";

  # Pre-fetch the histogram-quantile UDF binary to avoid in-container download issues
  histogramQuantile = pkgs.fetchurl {
    url = "https://github.com/SigNoz/signoz/releases/download/histogram-quantile%2Fv0.0.1/histogram-quantile_linux_arm64.tar.gz";
    hash = "sha256-5WBev/qCpFDrvN9s8Z2tVG4eQNUtvz4Dz9LS1bc5QhE=";
  };

  # Override cluster.xml to use localhost instead of container hostnames
  clusterXml = pkgs.writeText "cluster.xml" ''
    <?xml version="1.0"?>
    <clickhouse>
        <zookeeper>
            <node index="1">
                <host>zookeeper-1</host>
                <port>2181</port>
            </node>
        </zookeeper>
        <remote_servers>
            <cluster>
                <shard>
                    <replica>
                        <host>clickhouse</host>
                        <port>9000</port>
                    </replica>
                </shard>
            </cluster>
        </remote_servers>
    </clickhouse>
  '';

  opampConfig = pkgs.writeText "otel-collector-opamp-config.yaml" ''
    server_endpoint: ws://signoz:4320/v1/opamp
  '';

  composeFile = pkgs.writeText "docker-compose.yaml" (builtins.toJSON {
    version = "3";
    services = {
      init-clickhouse = {
        image = "clickhouse/clickhouse-server:${cfg.clickhouseVersion}";
        container_name = "signoz-init-clickhouse";
        command = [
          "bash"
          "-c"
          "cd /tmp && tar -xvzf /histogram-quantile.tar.gz && mv histogram-quantile /var/lib/clickhouse/user_scripts/histogramQuantile"
        ];
        restart = "on-failure";
        networks = ["signoz-net"];
        volumes = [
          "${histogramQuantile}:/histogram-quantile.tar.gz:ro"
          "user-scripts:/var/lib/clickhouse/user_scripts/"
        ];
      };

      zookeeper-1 = {
        image = "signoz/zookeeper:3.7.1";
        container_name = "signoz-zookeeper-1";
        user = "root";
        restart = "unless-stopped";
        networks = ["signoz-net"];
        volumes = [
          "zookeeper-1:/bitnami/zookeeper"
        ];
        environment = [
          "ZOO_SERVER_ID=1"
          "ALLOW_ANONYMOUS_LOGIN=yes"
          "ZOO_AUTOPURGE_INTERVAL=1"
          "ZOO_ENABLE_PROMETHEUS_METRICS=yes"
          "ZOO_PROMETHEUS_METRICS_PORT_NUMBER=9141"
        ];
        healthcheck = {
          test = ["CMD-SHELL" "curl -s -m 2 http://localhost:8080/commands/ruok | grep error | grep null"];
          interval = "30s";
          timeout = "5s";
          retries = 3;
        };
      };

      clickhouse = {
        image = "clickhouse/clickhouse-server:${cfg.clickhouseVersion}";
        container_name = "signoz-clickhouse";
        restart = "unless-stopped";
        networks = ["signoz-net"];
        depends_on = {
          init-clickhouse = { condition = "service_completed_successfully"; };
          zookeeper-1 = { condition = "service_healthy"; };
        };
        volumes = [
          "${clickhouseConfDir}/config.xml:/etc/clickhouse-server/config.xml:ro"
          "${clickhouseConfDir}/users.xml:/etc/clickhouse-server/users.xml:ro"
          "${clickhouseConfDir}/custom-function.xml:/etc/clickhouse-server/custom-function.xml:ro"
          "${clusterXml}:/etc/clickhouse-server/config.d/cluster.xml:ro"
          "user-scripts:/var/lib/clickhouse/user_scripts/"
          "clickhouse:/var/lib/clickhouse/"
        ];
        environment = ["CLICKHOUSE_SKIP_USER_SETUP=1"];
        healthcheck = {
          test = ["CMD" "wget" "--spider" "-q" "0.0.0.0:8123/ping"];
          interval = "30s";
          timeout = "5s";
          retries = 3;
        };
        ulimits = {
          nofile = { soft = 262144; hard = 262144; };
        };
      };

      signoz = {
        image = "signoz/signoz:v${cfg.version}";
        container_name = "signoz";
        restart = "unless-stopped";
        networks = ["signoz-net"];
        depends_on = {
          clickhouse = { condition = "service_healthy"; };
        };
        ports = ["${toString cfg.port}:8080"];
        volumes = [
          "sqlite:/var/lib/signoz/"
        ];
        environment = [
          "SIGNOZ_ALERTMANAGER_PROVIDER=signoz"
          "SIGNOZ_TELEMETRYSTORE_CLICKHOUSE_DSN=tcp://clickhouse:9000"
          "SIGNOZ_SQLSTORE_SQLITE_PATH=/var/lib/signoz/signoz.db"
          "SIGNOZ_TOKENIZER_JWT_SECRET=${cfg.jwtSecret}"
        ];
        healthcheck = {
          test = ["CMD" "wget" "--spider" "-q" "localhost:8080/api/v1/health"];
          interval = "30s";
          timeout = "5s";
          retries = 3;
        };
      };

      signoz-telemetrystore-migrator = {
        image = "signoz/signoz-otel-collector:v${cfg.otelCollectorVersion}";
        container_name = "signoz-telemetrystore-migrator";
        restart = "on-failure";
        networks = ["signoz-net"];
        depends_on = {
          clickhouse = { condition = "service_healthy"; };
        };
        environment = [
          "SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_DSN=tcp://clickhouse:9000"
          "SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_CLUSTER=cluster"
          "SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_REPLICATION=false"
          "SIGNOZ_OTEL_COLLECTOR_TIMEOUT=10m"
        ];
        entrypoint = ["/bin/sh"];
        command = [
          "-c"
          "/signoz-otel-collector migrate bootstrap && /signoz-otel-collector migrate sync up && /signoz-otel-collector migrate async up"
        ];
      };

      otel-collector = {
        image = "signoz/signoz-otel-collector:v${cfg.otelCollectorVersion}";
        container_name = "signoz-otel-collector";
        restart = "unless-stopped";
        networks = ["signoz-net"];
        depends_on = {
          clickhouse = { condition = "service_healthy"; };
        };
        entrypoint = ["/bin/sh"];
        command = [
          "-c"
          "/signoz-otel-collector migrate sync check && /signoz-otel-collector --config=/etc/otel-collector-config.yaml --manager-config=/etc/manager-config.yaml --copy-path=/var/tmp/collector-config.yaml"
        ];
        volumes = [
          "${otelCollectorConfig}:/etc/otel-collector-config.yaml:ro"
          "${opampConfig}:/etc/manager-config.yaml:ro"
        ];
        environment = [
          "OTEL_RESOURCE_ATTRIBUTES=host.name=signoz-host,os.type=darwin"
          "LOW_CARDINAL_EXCEPTION_GROUPING=false"
          "SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_DSN=tcp://clickhouse:9000"
          "SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_CLUSTER=cluster"
          "SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_REPLICATION=false"
          "SIGNOZ_OTEL_COLLECTOR_TIMEOUT=10m"
        ];
        ports = [
          "${toString cfg.otlpGrpcPort}:4317"
          "${toString cfg.otlpHttpPort}:4318"
        ];
      };
    };

    networks.signoz-net.name = "signoz-net";

    volumes = {
      clickhouse.name = "signoz-clickhouse";
      sqlite.name = "signoz-sqlite";
      zookeeper-1.name = "signoz-zookeeper-1";
      user-scripts.name = "signoz-user-scripts";
    };
  });

  startScript = pkgs.writeShellScript "signoz-start" ''
    export PATH="${pkgs.podman}/bin:${pkgs.podman-compose}/bin:$PATH"

    # Wait for podman machine to be running (managed by podman-init service)
    for i in $(seq 1 30); do
      if podman machine inspect podman-machine-default 2>/dev/null | ${pkgs.jq}/bin/jq -e '.[0].State == "running"' >/dev/null 2>&1; then
        break
      fi
      echo "Waiting for podman machine to be ready... ($i/30)"
      sleep 2
    done

    cleanup() {
      ${pkgs.podman}/bin/podman compose -f ${composeFile} -p signoz down
      exit 0
    }
    trap cleanup SIGTERM SIGINT

    ${pkgs.podman}/bin/podman compose -f ${composeFile} -p signoz up &
    wait $!
  '';
in
{
  options.services.signoz = {
    enable = mkEnableOption "SigNoz observability platform via Podman Compose";

    version = mkOption {
      type = types.str;
      default = "0.118.0";
      description = "SigNoz version.";
    };

    srcHash = mkOption {
      type = types.str;
      default = "sha256-AvuAYXrZ1ypCtZNb34gBN4tbchZbMrGJhBzy3Txh1ug=";
      description = "Hash of the SigNoz source archive (for fetchFromGitHub).";
    };

    otelCollectorVersion = mkOption {
      type = types.str;
      default = "0.144.2";
      description = "SigNoz OpenTelemetry Collector version.";
    };

    clickhouseVersion = mkOption {
      type = types.str;
      default = "25.5.6";
      description = "ClickHouse server image version.";
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Host port for the SigNoz UI and API.";
    };

    otlpGrpcPort = mkOption {
      type = types.port;
      default = 4317;
      description = "Host port for OTLP gRPC receiver.";
    };

    otlpHttpPort = mkOption {
      type = types.port;
      default = 4318;
      description = "Host port for OTLP HTTP receiver.";
    };

    jwtSecret = mkOption {
      type = types.str;
      default = "signoz-jwt-secret";
      description = "JWT secret for SigNoz tokenizer. Change this in production.";
    };
  };

  config = mkIf cfg.enable {
    launchd.user.agents.signoz = {
      serviceConfig = {
        Label = "io.signoz.compose";
        ProgramArguments = [
          "${startScript}"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/signoz.log";
        StandardErrorPath = "/tmp/signoz.log";
      };
    };
  };
}
