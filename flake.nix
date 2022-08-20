{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      mkPackage = system:
        let
          pkgs = nixpkgs.legacyPackages."${system}";
          proc_cpuinfo = ./proc_cpuinfo.txt;
        in
        pkgs.poetry2nix.mkPoetryApplication {
          projectDir = ./.;
          # Hacks to fix: https://github.com/NixOS/nixpkgs/issues/122993
          overrides = pkgs.poetry2nix.overrides.withDefaults (self: super: {
            rpi-gpio = super.rpi-gpio.overridePythonAttrs (old: {
              postPatch = ''
                substituteInPlace source/cpuinfo.c \
                  --replace "/proc/cpuinfo" "${proc_cpuinfo}"
              '';
            });
            gpiozero = super.gpiozero.overridePythonAttrs (old: {
              postPatch = ''
                substituteInPlace gpiozero/pins/local.py \
                  --replace "/proc/cpuinfo" "${proc_cpuinfo}"
              '';
            });
          });
        };
    in
    {
      overlays.default = final: prev: {
        cover = self.packages.${prev.system}.default;
      };
      nixosModules.default = import ./module.nix;

      packages = {
        aarch64-linux.default = mkPackage "aarch64-linux";
        x86_64-linux.default = mkPackage "x86_64-linux";
      };
    };
}
