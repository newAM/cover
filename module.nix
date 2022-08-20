{ config, lib, pkgs, ... }:

let
  cfg = config.services.cover;
in
{
  options.services.cover = with lib; {
    enable = mkEnableOption "cover";
  };

  config = lib.mkIf cfg.enable {
    systemd.services.cover = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "idle";
        KillSignal = "SIGINT";
        ExecStart = "${pkgs.cover}/bin/cover";
        Restart = "on-failure";
        RestartSec = 10;
      };
    };
  };
}
