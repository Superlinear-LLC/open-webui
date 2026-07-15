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
              allowUnsupportedSystem = true;
            };
          };
          pythonPackages = pkgs.python312Packages.overrideScope (final: prev: {
            # nixpkgs-unstable currently runs jaraco-test's suite with pytest 9,
            # but that suite crashes during report generation. It is only a
            # transitive test dependency of Open WebUI, so skip its broken test
            # hook while retaining the package itself.
            jaraco-test = prev.jaraco-test.overridePythonAttrs (_: {
              doCheck = false;
            });
          });
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
