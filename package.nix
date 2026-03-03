{
  makeRustPlatform,
  cargo-nightly,
  rustc-nightly,

  cmakeMinimal,

  packsquash-src,

  ...
}@pkgs:
let
  rustPlatform = makeRustPlatform {
    cargo = cargo-nightly;
    rustc = rustc-nightly;
  };
in
  # null
  rustPlatform.buildRustPackage (self: {
    pname = "packsquash";
    version = "0.4.1";

    src = packsquash-src;
    cargoHash = "sha256-dx2Cm2zNr9FARd1fc6ehynxrA1qHwtQQGMmEbGuc0dk=";

    nativeBuildInputs = with pkgs; [
      cmakeMinimal
    ];

    checkFlags = [
      # Tests whether or not it can find and access the DBus
      # machine-id on this system. This isn't available in the build
      # sandbox, so we skip the test here.
      #
      # Original comments on this test:
      #   Gets the D-Bus and/or systemd generated machine ID.
      #   This machine ID is 128-bit wide, and is intended to be
      #   constant for all the lifecycle of the OS install, no
      #   matter if hardware is replaced or some configuration is
      #   changed.
      #
      #   Although originally Linux-specific, D-Bus can be run in
      #   BSD derivatives, and Linux is pretty influential in the
      #   Unix world, so it's worth trying on most Unix-like systems.
      #
      #   Further reading:
      #   - <https://www.freedesktop.org/software/systemd/man/machine-id.html>
      #   - <https://unix.stackexchange.com/questions/396052/missing-etc-machine-id-on-freebsd-trueos-dragonfly-bsd-et-al>
      "--skip=dbus_machine_id_works"

      # Tests whether or not it can find and access the DMI serial
      # numbers on this system. This isn't available in the build
      # sandbox, so we skip the test here.
      #
      # Original comments on this test:
        #   Gets a system identifier that aggregates the DMI serial
        #   numbers collected by the udev database, provided by the BIOS.
        #   Unlike directly reading the DMI product ID from sysfs,
        #   this method does not require root privileges, and takes
        #   into account more serial numbers, but assumes that a suitable
        #   udev daemon with a compatible database format is running. On
        #   modern Linux distributions, this is usually implemented by
        #   systemd-udevd.
        #
        #   Further reading:
        #   - <https://man7.org/linux/man-pages/man7/udev.7.html>
        #   - <https://www.phoronix.com/news/Linux-DIMM-Details-As-Root>
        #   - <https://man7.org/linux/man-pages/man8/systemd-udevd.service.8.html>
        "--skip=get_aggregated_dmi_serial_numbers_id"
      ];
  })
