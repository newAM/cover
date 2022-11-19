{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    src = builtins.path {
      path = ./.;
      name = "cover";
    };

    mkPackage = system: let
      pkgs = nixpkgs.legacyPackages."${system}";
      proc_cpuinfo = ./proc_cpuinfo.txt;
    in
      pkgs.poetry2nix.mkPoetryApplication {
        projectDir = src;
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
          systemd-python = super.systemd-python.overridePythonAttrs (old: {
            nativeBuildInputs =
              (old.nativeBuildInputs or [])
              ++ [
                self.setuptools
              ];
          });
        });
      };
  in {
    overlays.default = final: prev: {
      cover = self.packages.${prev.system}.default;
    };
    nixosModules.default = import ./module.nix;

    packages = {
      aarch64-linux.default = mkPackage "aarch64-linux";
      x86_64-linux.default = mkPackage "x86_64-linux";
    };

    checks.x86_64-linux = let
      nixSrc = nixpkgs.lib.sources.sourceFilesBySuffices src [".nix"];
      pySrc = nixpkgs.lib.sources.sourceFilesBySuffices src [".py"];
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      pkg-aarch64-linux = self.packages.aarch64-linux.default;
      pkg-x86_64-linux = self.packages.x86_64-linux.default;

      black = pkgs.runCommand "black" {} ''
        ${pkgs.python3Packages.black}/bin/black --config ${./pyproject.toml} ${pySrc}
        touch $out
      '';

      flake8 =
        pkgs.runCommand "flake8"
        {
          buildInputs = with pkgs.python3Packages; [
            flake8
            flake8-bugbear
            pep8-naming
          ];
        }
        ''
          flake8 --max-line-length 88 ${pySrc}
          touch $out
        '';

      alejandra = pkgs.runCommand "alejandra" {} ''
        ${pkgs.alejandra}/bin/alejandra --check ${nixSrc}
        touch $out
      '';

      statix = pkgs.runCommand "statix" {} ''
        ${pkgs.statix}/bin/statix check ${nixSrc}
        touch $out
      '';
    };
  };
}
