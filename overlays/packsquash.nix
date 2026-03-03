self:
_: super:
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
}
