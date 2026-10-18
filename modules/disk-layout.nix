/*
  Disk layout for an installed easy-nix.

  Two partitions, both referenced by **partition label** and never by device node.
  That is the whole point: the installer can target /dev/sda, /dev/nvme0n1 or
  /dev/mmcblk0, and every later `nixos-rebuild` still resolves the same filesystems.
  A config that hardcoded `/dev/sda2` would rebuild a machine whose root is elsewhere.

  The installer reproduces this layout with sgdisk + mkfs (see
  `modules/installer/install.sh`); keep the two in step.
*/
{ lib, ... }:
{
  fileSystems."/" = {
    device = "/dev/disk/by-partlabel/NIXROOT";
    fsType = "ext4";
    options = [ "noatime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-partlabel/ESP";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
    # Five generations in the menu: enough to roll back through a bad update,
    # few enough that a 32 GB disk is not filled by kernels.
    systemd-boot.configurationLimit = lib.mkDefault 5;
  };

  # Suspend-to-disk is out of scope; the appliance reboots.
  swapDevices = [ ];
}
