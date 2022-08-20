{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      mkPackage = system:
        let
          pkgs = nixpkgs.legacyPackages."${system}";
        in
        pkgs.poetry2nix.mkPoetryScriptsPackage {
          projectDir = ./.;
          python = pkgs.python3;
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
