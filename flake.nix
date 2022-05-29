{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    poetry2nix.url = "github:nix-community/poetry2nix";
  };

  outputs = { self, nixpkgs, flake-utils, poetry2nix }:
    nixpkgs.lib.recursiveUpdate
      {
        overlays.default = final: prev: {
          cover = self.packages.${prev.system}.default;
        };
        nixosModules.default = import ./module.nix;

        overlay = nixpkgs.lib.composeManyExtensions [
          poetry2nix.overlay
          (final: prev: {
            cover = prev.poetry2nix.mkPoetryApplication {
              projectDir = ./.;
            };
          })
        ];
      }
      (flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlay ];
          };
        in
        {
          packages.default = pkgs.cover;
        }));
}
