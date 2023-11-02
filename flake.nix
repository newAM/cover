{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    poetry2nix.url = "github:nix-community/poetry2nix";
    poetry2nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    poetry2nix,
  }: let
    overlay = final: prev: {
      cover = prev.poetry2nix.mkPoetryApplication {
        projectDir = self;
        # Hacks to fix: https://github.com/NixOS/nixpkgs/issues/122993
        overrides = prev.poetry2nix.overrides.withDefaults (pyFinal: pyPrev: {
          rpi-gpio = pyPrev.rpi-gpio.overridePythonAttrs (old: {
            postPatch = ''
              substituteInPlace source/cpuinfo.c \
                --replace "/proc/cpuinfo" "${./proc_cpuinfo.txt}"
            '';
          });
          gpiozero = pyPrev.gpiozero.overridePythonAttrs (old: {
            postPatch = ''
              substituteInPlace gpiozero/pins/local.py \
                --replace "/proc/cpuinfo" "${./proc_cpuinfo.txt}"
            '';
          });
          systemd-python = pyPrev.systemd-python.overridePythonAttrs (old: {
            nativeBuildInputs =
              (old.nativeBuildInputs or [])
              ++ [
                pyFinal.setuptools
              ];
          });
        });
      };
    };

    pkgsForSys = system:
      import nixpkgs {
        inherit system;
        overlays = [
          poetry2nix.overlays.default
          overlay
        ];
      };

    forAllSystems = nixpkgs.lib.genAttrs ["aarch64-linux" "x86_64-linux"];
  in {
    overlays.default = overlay;
    nixosModules.default = import ./module.nix;

    packages = forAllSystems (system: {
      default = let pkgs = pkgsForSys system; in pkgs.cover;
    });

    checks.x86_64-linux = let
      nixSrc = nixpkgs.lib.sources.sourceFilesBySuffices self [".nix"];
      pySrc = nixpkgs.lib.sources.sourceFilesBySuffices self [".py"];
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
