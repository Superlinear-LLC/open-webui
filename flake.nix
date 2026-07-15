{
  description = "Open WebUI 0.10.2 Nix package";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs = { nixpkgs, ... }:
    {
      packages = builtins.listToAttrs (map (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
              allowBroken = true;
            };
          };
          pythonPackages = pkgs.python312Packages;
          package = pkgs.callPackage ./nix/package.nix {
            inherit pythonPackages;
          };
        in {
          name = system;
          value = {
            open-webui = package;
            open-webui-frontend = package.frontend;
            default = package;
          };
        }) [ "aarch64-darwin" "x86_64-darwin" ]);
    };
}
