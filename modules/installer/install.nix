/*
  The installer: `easy-nix-install`, on the live medium.

  What it does in the order it does it, because the order is the safety property:

    1. refuses to run unless it is root, on a whole block device, not mounted, and
       not the medium it was booted from;
    2. partitions by label (ESP + NIXROOT), matching `modules/disk-layout.nix`. The
       installed system therefore mounts by label and keeps working whatever disk it
       ends up on;
    3. installs with `nixos-install --flake /etc/easy-nix#easy-nix` - the medium's own
       copy of the configuration, so the install is what you booted, not whatever the
       network serves today;
    4. clones the repository into the installed system so it can fast-forward its own
       configuration later. If there is no network, it says so instead of pretending:
       automatic updates are off until the checkout exists.

  There is no encryption and no dual boot, and the README says so rather than leaving
  it to be found out. Adding LUKS is a change of one file (`disk-layout.nix`) plus a
  line in the partitioning step below.
*/
{
  config,
  lib,
  pkgs,
  inputs,
  flakeSelf,
  ...
}:
let
  cfg = config.easyNix;

  install = pkgs.writeShellApplication {
    name = "easy-nix-install";
    runtimeInputs = with pkgs; [
      gptfdisk
      dosfstools
      e2fsprogs
      util-linux
      nixos-install-tools
      # `nixos-install` is a shell script that shells out to `nix`. Without it here, the
      # wrapper's PATH has the installer and not the tool the installer calls, and a run
      # that had already partitioned and mounted the disk dies on "nix: command not found"
      # two hundred lines in.
      config.nix.package
      git
      coreutils
      findutils
    ];
    text = ''
      host="easy-nix"
      config_dir="/etc/easy-nix"
      assume_yes=0
      disk=""

      usage() {
        cat <<'USAGE'
      easy-nix-install [--disk DEVICE] [--yes]

        --disk DEVICE  install onto DEVICE (e.g. /dev/sda, /dev/nvme0n1)
        --yes          do not ask for confirmation; only for automated installs

      Everything on the target device is destroyed. There is no undo.
      USAGE
      }

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --disk)
            disk="''${2:?--disk needs a device}"
            shift 2
            ;;
          --yes)
            assume_yes=1
            shift
            ;;
          -h | --help)
            usage
            exit 0
            ;;
          *)
            echo "unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
        esac
      done

      if [ "$(id -u)" -ne 0 ]; then
        echo "easy-nix-install must run as root" >&2
        exit 1
      fi

      # The configuration boots through systemd-boot, which is UEFI only. Refusing here
      # is the honest outcome: the alternative is a machine that installs happily and
      # then cannot boot, with no error to explain why.
      if [ ! -d /sys/firmware/efi ]; then
        echo "This machine booted in legacy BIOS mode; easy-nix needs UEFI." >&2
        echo "Booting it from a BIOS-only machine would need a bios_grub partition and" >&2
        echo "GRUB on a device node, neither of which this configuration sets." >&2
        exit 1
      fi

      if [ -z "$disk" ]; then
        echo "Disks:"
        lsblk -dno NAME,SIZE,TYPE,MODEL
        echo
        printf 'Target disk (e.g. /dev/sda), ALL DATA ON IT WILL BE ERASED: '
        read -r disk
      fi

      if [ ! -b "$disk" ]; then
        echo "$disk is not a block device" >&2
        exit 1
      fi

      case "$disk" in
        *[0-9]) esp="''${disk}p1"; root="''${disk}p2" ;;
        *) esp="$disk"1; root="$disk"2 ;;
      esac

      # Refuse the medium we booted from: the store is read-only on it, and wiping it
      # mid-install is a failure mode with no recovery on a machine with no other OS.
      medium=$(findmnt -n -o SOURCE --target /iso 2>/dev/null || true)
      if [ -n "$medium" ] && [ "$(basename "$medium")" = "$(basename "$disk")" ]; then
        echo "$disk is the medium you booted from" >&2
        exit 1
      fi

      if [ -n "$(lsblk -no MOUNTPOINTS "$disk" | tr -d '[:space:]')" ]; then
        echo "$disk has mounted filesystems, refusing to touch it" >&2
        exit 1
      fi

      if [ "$assume_yes" -eq 0 ]; then
        echo "About to ERASE $disk and install easy-nix on it."
        printf 'Type ERASE to continue: '
        read -r answer
        if [ "$answer" != "ERASE" ]; then
          echo "cancelled"
          exit 1
        fi
      fi

      echo "==> partitioning $disk"
      sgdisk --zap-all "$disk"
      sgdisk -n 1:0:+1G -t 1:ef00 -c 1:ESP "$disk"
      sgdisk -n 2:0:0 -t 2:8300 -c 2:NIXROOT "$disk"
      # `sgdisk` returning does not mean the partitions exist yet: the kernel revalidates
      # the table in the background. Measured in a virtual machine, the mount of the root
      # partition failed with a bad superblock while the kernel only announced partition 2
      # a second later - the format had gone to a device node the kernel had not mapped.
      # `partprobe` is `parted`'s, and this wrapper's PATH carries util-linux instead, so
      # it was never there to ask; the `|| true` that swallowed the complaint hid that.
      partx -u "$disk" 2>/dev/null || true
      udevadm settle || true
      for _ in $(seq 1 40); do
        [ -b "$esp" ] && [ -b "$root" ] && break
        sleep 0.5
      done
      if [ ! -b "$esp" ] || [ ! -b "$root" ]; then
        echo "the kernel never announced $esp and $root:" >&2
        lsblk "$disk" >&2 || true
        exit 1
      fi

      echo "==> formatting"
      mkfs.fat -F32 -n ESP "$esp"
      mkfs.ext4 -L NIXROOT -F "$root"

      echo "==> mounting"
      umount -R /mnt 2>/dev/null || true
      # Not guaranteed to exist on a medium built from a plain system configuration,
      # which has no installer profile to create it.
      mkdir -p /mnt
      mount "$root" /mnt
      # After the root, never before: a `boot` directory made on the medium's own /mnt is
      # hidden the moment the target's root is mounted over it, and the filesystem that was
      # just created on the target has no `boot` of its own. In the other order the ESP
      # mount fails with "the mount point does not exist", which reads like a problem with
      # the ESP and is a problem with the order.
      mkdir -p /mnt/boot
      mount "$esp" /mnt/boot

      echo "==> installing easy-nix (this takes a while)"
      nixos-install --flake "$config_dir#$host" --no-root-password

      echo "==> giving the installed system a checkout it can update itself from"
      mkdir -p /mnt/etc
      if git clone --quiet --depth 1 "${cfg.flakeRef}" /mnt/etc/easy-nix 2>/dev/null; then
        echo "    cloned ${cfg.flakeRef}"
      else
        echo "WARNING: could not clone ${cfg.flakeRef}: no network?" >&2
        echo "         automatic updates stay off until a checkout exists at" >&2
        echo "         /etc/easy-nix on the installed system." >&2
      fi

      umount -R /mnt

      echo
      echo "easy-nix is installed. Remove the medium and reboot."
    '';
  };
in
{
  # Only where a host asked for it (`easyNix.autoInstall`): the medium the install test
  # boots, never the released one. It announces the outcome on the serial console in the
  # same shape as the machine's own marker, so a machine can wait for it, and it powers
  # the machine off rather than leaving it waiting for someone.
  systemd.services.easy-nix-autoinstall = lib.mkIf (cfg.autoInstall != null) {
    description = "Install easy-nix onto an attached disk, unattended";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # An install takes as long as it takes; the caller has its own deadline.
      TimeoutStartSec = "infinity";
      # What the installer says goes to the console as well as to the journal. The
      # journal of a machine that has been powered off, and whose disk is a temporary
      # image, cannot be read afterwards - the serial console is the only channel the
      # test can read, and without this an early refusal is invisible.
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
    script = ''
      set -x
      if ${install}/bin/easy-nix-install --disk ${lib.escapeShellArg cfg.autoInstall} --yes; then
        msg="EASY_NIX_INSTALLED device=${cfg.autoInstall}"
      else
        msg="EASY_NIX_INSTALL_FAILED device=${cfg.autoInstall}"
      fi
      echo "$msg" > /dev/ttyS0 || true
      echo "$msg" > /dev/console || true
      sync
      systemctl poweroff --no-block || true
    '';
  };

  # The configuration being installed, on the medium. This is what makes the install
  # offline-capable and reproducible: what you boot is what gets installed.
  environment.etc."easy-nix".source = flakeSelf.outPath;

  environment.systemPackages = [
    install
    pkgs.less # so an operator can read the config they are installing
    (pkgs.makeDesktopItem {
      name = "easy-nix-install";
      desktopName = "Install easy-nix";
      comment = "Erase a disk and install easy-nix on it";
      icon = "system-software-install";
      # The terminal is named explicitly: niri has no concept of `Terminal=true`, so a
      # script that prompts would be launched with no tty at all.
      exec = "${pkgs.foot}/bin/foot -e sudo ${install}/bin/easy-nix-install";
      categories = [ "System" ];
    })
  ];

  # Everything needed to *evaluate* the configuration on the medium. Without the
  # inputs in the store, `nixos-install` would have to reach the network to resolve
  # the flake it is currently running from. Set inside the variant: `isoImage` is
  # declared by the image module, which only that variant imports.
  image.modules.iso.isoImage.storeContents = [
    flakeSelf.outPath
  ]
  ++ (with inputs; [
    flake-parts
    home-manager
    nixos-hardware
    treefmt-nix
    git-hooks
    llm-agents
    nixpkgs
  ]);
}
