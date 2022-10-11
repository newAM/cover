{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.cover;
in {
  options.services.cover = with lib; {
    enable = mkEnableOption "cover";

    hostname = mkOption {
      type = types.str;
      description = ''
        Hostname or IP of the MQTT server.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.cover = {
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "idle";
        KillSignal = "SIGINT";
        ExecStart = "${pkgs.cover}/bin/cover ${cfg.hostname}";
        Restart = "on-failure";
        RestartSec = 10;
      };
      environment.GPIOZERO_PIN_FACTORY = "native";
    };
  };
}
