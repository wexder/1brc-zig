{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    devenv.url = "github:cachix/devenv";
    zig.url = "github:mitchellh/zig-overlay";
  };

  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  outputs = { self, nixpkgs, zig, devenv, ... } @ inputs:
    let
      pkgs = nixpkgs.legacyPackages."x86_64-linux";
      zigpkg = zig.packages."x86_64-linux";
    in
    {
      devShell.x86_64-linux = devenv.lib.mkShell {
        inherit inputs pkgs;

        modules = [
          ({ pkgs, lib, ... }: {

            # This is your devenv configuration
            packages = [
              zigpkg.master
              pkgs.zls
              pkgs.samply
            ];

            enterShell = ''
            '';
          })
        ];
      };
    };
}
