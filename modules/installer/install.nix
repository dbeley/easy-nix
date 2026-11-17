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
  it to be found out. Adding LUKS is a change of `disk-layout.nix` plus a line in the
  partitioning step below.
*/
{
  config,
  lib,
  pkgs,
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
      # `nixos-install` shells out to `nix`; without it here the wrapper's PATH has the
      # installer and not the tool the installer calls, and the run dies on
      # "nix: command not found" with the disk already partitioned and mounted.
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

      # systemd-boot is UEFI only. Refusing here beats a machine that installs happily and
      # then cannot boot, with no error to explain why: BIOS boot would need a bios_grub
      # partition and GRUB on a device node, neither of which this configuration sets.
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
      # the table in the background, and a format sent to a node it has not mapped yet
      # fails with a bad superblock. Wait for both, bounded, before touching them.
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
      # A medium built from a plain system configuration has no installer profile to
      # create this directory.
      mkdir -p /mnt
      mount "$root" /mnt
      # After the root, never before: the filesystem just created on the target has no
      # `boot` of its own, and a `boot` made on the medium's /mnt would be hidden the moment
      # the target's root is mounted over it.
      mkdir -p /mnt/boot
      mount "$esp" /mnt/boot

      echo "==> installing easy-nix (this takes a while)"
      # `nixos-install` works in the *target's* store, which starts empty, so without a
      # substituter it builds the system there from source - and the medium carries no
      # stdenv to borrow. Naming the cache reduces the install to a substitution of
      # everything except this configuration, the one thing the medium genuinely has.
      nixos-install --flake "$config_dir#$host" --no-root-password \
        --option substituters "https://cache.nixos.org"

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
      # What the installer says goes to the console as well as to the journal: the journal
      # of a machine that has been powered off, whose disk is a temporary image, cannot be
      # read afterwards. The serial console is the only channel the test has.
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
    script = ''
      set -x
      # Wait until the network not only exists but resolves something.
      #
      # `network-online.target` is satisfied as soon as NetworkManager reports it, which can
      # be before the resolver answers, and the installer's first lookup then fails on a
      # network that was only early. Bounded, so a medium without a network still reaches
      # the installer and fails with the installer's own message rather than this loop's.
      for _ in $(seq 1 60); do
        getent hosts cache.nixos.org >/dev/null 2>&1 && break
        sleep 1
      done
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

  # The configuration being installed, carried on the medium rather than fetched: what you
  # boot is what gets installed.
  #
  # A network is still required to install it. `nixos-install` assembles the system in the
  # *target's* store, which is empty, from the cache - so what the medium saves is the
  # configuration itself, the only part no cache can supply.
  environment.etc."easy-nix".source = flakeSelf.outPath;

  environment.systemPackages = [
    install
    pkgs.less # so an operator can read the config they are installing
    (pkgs.makeDesktopItem {
      name = "easy-nix-install";
      desktopName = "Install easy-nix";
      comment = "Erase a disk and install easy-nix on it";
      icon = "system-software-install";
      # The terminal is named explicitly: a Wayland compositor has no concept of `Terminal=true`, so a
      # script that prompts would be launched with no tty at all.
      exec = "${pkgs.foot}/bin/foot -e sudo ${install}/bin/easy-nix-install";
      categories = [ "System" ];
    })
  ];

  # Everything the medium must carry to install: what a flake evaluation needs, and the
  # system itself.
  #
  # This is `isoImage.storeContents`, which feeds the store the medium boots with *and* the
  # registration file that makes its paths valid (`nix-store --load-db <
  # /nix/store/nix-path-registration`).
  #
  # It does not make the install offline: `nixos-install` works in the *target's* store, so
  # the medium's closure only turns a rebuild into a substitution. The rest is derivations
  # and sources, which no ISO carries.
  image.modules.iso.isoImage.storeContents = lib.unique (
    [ flakeSelf.outPath ]
    ++ (
      let
        # Everything a flake evaluation needs, the inputs of the inputs included: evaluating
        # the configuration makes flake-parts resolve its own lock, which asks for
        # nix-community/nixpkgs.lib, and a medium missing it fetches it during the install
        # and dies on a host lookup with the disk already partitioned and mounted.
        #
        # No filter on `outPath`: in the pure evaluation that builds the image, an input
        # whose source is not yet in the store has no `outPath`, so the guard would drop
        # exactly the inputs that need fetching. `input.inputs or {}` is for inputs that are
        # not flakes; `isAttrs` is for inputs that are plain paths.
        walk =
          set:
          lib.concatLists (
            lib.mapAttrsToList (
              _: input: lib.optionals (lib.isAttrs input) ([ input.outPath ] ++ (walk (input.inputs or { })))
            ) set
          );
      in
      walk flakeSelf.inputs
    )
    # And the system itself, so that installing it is a copy rather than a build.
    #
    # Sharing the applications is not enough: this medium runs `easy-nix-live`, a different
    # system from the `easy-nix` the installer installs, so that system's store path is
    # absent and `nixos-install` sets out to build it - then fails on the bootstrap stdenv,
    # a message about a compiler while the fault is an image that does not carry what it
    # installs.
    #
    # The host name is the one the script above installs; the installer module is imported by
    # media only, so this costs the light boot image nothing.
    ++ [ flakeSelf.nixosConfigurations.easy-nix.config.system.build.toplevel ]
  );
}
