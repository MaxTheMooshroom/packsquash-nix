{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs-lib.follows = "flake-parts/nixpkgs-lib";

    nixpkgs.url = "github:NixOS/nixpkgs/25.11";

    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";

    rust-nightly = {
      url = ./rust-nightly.nix;
      flake = false;
    };

    packsquash = {
      url = "github:ComunidadAylas/PackSquash/v0.4.1";
      flake = false;
    };

    package = {
      url = ./package.nix;
      flake = false;
    };

    mk-squash-config = {
      url = ./lib/mk-squash-config.nix;
      flake = false;
    };

    squash-pack = {
      url = ./lib/squash-pack.nix;
      flake = false;
    };

    flake-modules.url = "github:MaxTheMooshroom/flake-modules";
  };

  outputs = { self, nixpkgs-lib, flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs-lib.lib.systems.flakeExposed;

      imports = [
        inputs.flake-modules.flakeModules.lib
        inputs.flake-modules.flakeModules.overlays
      ];

      overlays.nixpkgs = [
        inputs.rust-overlay.overlays.default
        (import inputs.rust-nightly.outPath)
      ];

      perSystem = { system, inputs', self', lib, pkgs, ... }: {
        packages = {
          default = self'.packages.packsquash;

          packsquash = pkgs.callPackage inputs.package.outPath {
            packsquash-src = inputs.packsquash;
          };
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            self'.packages.packsquash

            cargo-nightly
            rustc-nightly
            rustfmt
          ];
        };
      };

      flake = {
        lib = {
          mkSquashConfig = inputs.mk-squash-config;

          squashPack = inputs.squash-pack;
        };

        overlays = {
          default = self.overlays.packsquash;

          packsquash = _: super:
            let
              inherit (super) lib;
              inherit (super.stdenv.hostPlatform) system;

              mc-utils = super.mc-utils or (
                lib.makeScope super.newScope (
                  final: {
                    packages = lib.makeScope final.newScope (_: {});

                    lib = lib.makeScope final.newScope (_: {});
                  }
                )
              );
            in {
              mc-utils = mc-utils.overrideScope (final: prev: {
                packages = prev.packages.overrideScope (final': prev': {
                  packsquash = self.packages.${system}.packsquash;
                });

                lib = prev.lib.overrideScope (final': prev': {
                  mkSquashConfig = super.callPackage self.lib.mkSquashConfig {};

                  squashPack = super.callPackage self.lib.squashPack {};
                });
              });
            };
        };
      };
    };
}
