/*
  ARM flavour: experimental, and not the same product.

  NixOS has no installer ISO for ARM hardware, so the deliverable is a flashable
  SD/eMMC image built per board. Steam (x86-only) and Flathub are absent: fewer moving
  parts on a board nobody will debug.

  The kernel, firmware and partition layout come from `nixos-hardware` for the board in
  question. Raspberry Pi 4/5 is the assumed target; change the imported profile, and
  the firmware partition offset in the board module, for anything else.
*/
{
  config,
  inputs,
  ...
}:
{
  imports = [
    ../../modules/desktop/wayland.nix
    ../../modules/apps/browsers.nix
    ../../modules/apps/office.nix

    inputs.nixos-hardware.nixosModules.raspberry-pi-4
  ];

  # Everything that only makes sense on a bootable medium lives inside the `sd-card`
  # variant: `sdImage` is declared by the image module, which the host configuration
  # does not import.
  image.modules.sd-card = {
    # Serial console on the GPIO header, which is how a board with no screen is
    # debugged.
    boot.kernelParams = [
      "console=ttyAMA0,115200"
      "console=tty1"
    ];

    # Named after the board family rather than after x86 image conventions.
    image.baseName = "easy-nix-arm-${config.system.nixos.label}";

    sdImage.compressImage = true;
  };

  easyNix = {
    enable = true;
  };

  # No swap on flash storage beyond ZRAM: an SD card is the slowest swap device there
  # is, and swapping to it shortens its life.
  zramSwap.memoryPercent = 100;
}
