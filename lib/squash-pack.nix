{ lib, stdenvNoCC, packsquash, ... }@pkgs:
/**
  squash-config-proto: a function that produces a final
  config file for packsquash from params `pname`, `version`,
  and `out`.

  Generally speaking, this parameter will be the result of
  the [mk-squash-config](./mk-squash-config.nix) function.
*/
squash-config:
{
  /** The pack's name. */
  pname,

  /** The pack's version. */
  version,

  /**
    The packsquash derivation to use.
    Default: pkgs.packsquash (from this flake's `overlays.packsquash`)
  */

  ...
}:
stdenvNoCC.mkDerivation {
  inherit pname version;

  name = "${pname}-${version}.zip";
  src = squash-config.pack_directory;

  buildInputs = [ packsquash squash-config ];

  buildPhase = ''
    printf 'output_file_path=$${out}\n${
      builtins.readFile squash-config
    }' | packsquash --color --no-emoji
  '';
}
