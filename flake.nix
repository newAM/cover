{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, crane, flake-utils }:
    nixpkgs.lib.recursiveUpdate
      (flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ]
        (system:
          let
            pkgs = nixpkgs.legacyPackages.${system};
            cargoToml = nixpkgs.lib.importTOML ./Cargo.toml;
            craneLib = crane.lib.${system};

            commonArgs.src = ./.;

            cargoArtifacts = craneLib.buildDepsOnly commonArgs;
          in
          rec {
            devShells.default = pkgs.mkShell {
              inputsFrom = [ packages.default ];
              shellHook = commonArgs.preBuild;
            };

            packages.default = craneLib.buildPackage (commonArgs // {
              inherit cargoArtifacts;
            });

            checks = {
              pkgs = packages.default;

              clippy = craneLib.cargoClippy (commonArgs // {
                inherit cargoArtifacts;
              });

              rustfmt = craneLib.cargoFmt { src = ./.; };

              nixpkgs-fmt = pkgs.runCommand "nixpkgs-fmt" { } ''
                ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt --check ${./.}
                touch $out
              '';

              statix = pkgs.runCommand "statix" { } ''
                ${pkgs.statix}/bin/statix check ${./.}
                touch $out
              '';
            };
          }
        ))
      {
        overlays.default = final: prev: {
          cover = self.packages.${prev.system}.default;
        };
        nixosModules.default = import ./module.nix;
      };
}
