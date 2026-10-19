/*
  What turns a system configuration into a bootable medium.

  Two things a live image needs that an installed system does not:

    - a marker on the serial console once userspace is reached, so a boot test can
      assert "it boots" without a screen or a human;
    - USB and EFI booting, because the medium will be written to a stick and plugged
      into a machine whose firmware is UEFI-only.

  Everything here is defined **inside the `iso` image variant**, not on the host.
  `isoImage` is declared by the image module, which only that variant imports: setting
  it on the host configuration would be a definition of an option that does not exist
  there. `image.modules.<variant>` is the supported way to specialise an image - the
  same idea as `specialisation`, one level up.

  The marker writes to /dev/ttyS0 explicitly. `/dev/console` is not reliable for this:
  which device it points at depends on the order of the `console=` arguments, so a
  marker written there can end up nowhere. And `boot.consoleLogLevel` is the option
  that actually raises kernel verbosity - putting `loglevel=` in `boot.kernelParams`
  loses to the value nixpkgs appends afterwards, leaving the serial console mute and
  every boot failure undiagnosable.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
{
  image.modules.iso = {
    # The serial console, the kernel verbosity and the ready marker live in
    # `modules/base.nix`: an installed machine needs them as much as a medium does, and
    # the install test reads the marker from the system it has just installed.

    isoImage = {
      makeBiosBootable = true;
      makeEfiBootable = true;
      makeUsbBootable = true;
      # 32 characters maximum, and it becomes the filesystem label of the medium.
      volumeID = "EASY_NIX";
    };

    # A medium is the one system that has to mount filesystems it did not boot from: the
    # installer formats an ext4 root and a vfat ESP, and mounting either needs the driver
    # in this system's closure. A medium has no `fileSystems` of its own, so nothing else
    # pulls them in, and `mount` then fails on a partition `mkfs` has just written
    # perfectly - it reports a bad superblock, which sends you looking at the wrong piece
    # of the machine. Naming them here also makes the build resolve them, so a driver that
    # does not exist fails the build instead of the installation.
    boot.kernelModules = [
      "ext4"
      "vfat"
    ];

    # iso-image.nix assigns this without `mkDefault`, so overriding it has to be a force.
    image.baseName = lib.mkForce "easy-nix-${config.system.nixos.label}";

    # Tools a person on the console expects to find, without opening a browser first.
    environment.systemPackages = with pkgs; [
      parted
      gptfdisk
      dosfstools
      e2fsprogs
      smartmontools
      pciutils
    ];
  };
}
