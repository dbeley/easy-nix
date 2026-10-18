/*
  Powerwash: put the machine back to the state it had the day it was installed,
  without a bootable medium.

  What it does, in order, and what it deliberately does not:

    - removes the local override file (that is factory state, and the command has to
      be the one place allowed to touch it)
    - resets the configuration checkout to its remote (`reset --hard` is correct
      *here*: the operator asked for destruction, and the service that runs on its own
      never does this)
    - empties the user's home and restores the skeleton
    - makes the pristine system the next boot target

  It does not reinstall the operating system or reformat the disk: a machine that has
  to be handed to someone else is reset, not re-provisioned. Reinstalling means booting
  the ISO, which is the honest boundary to document.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.easyNix;
  notify = import ./notify.nix { inherit pkgs; };

  powerwash = pkgs.writeShellApplication {
    name = "easy-nix-powerwash";
    runtimeInputs = [
      pkgs.git
      pkgs.coreutils
      pkgs.util-linux
      pkgs.nixos-rebuild
      pkgs.nix
      pkgs.findutils
    ];
    text = ''
      dir="${cfg.configDir}"
      user="${config.users.users.easy.name or "easy"}"
      host="${config.networking.hostName}"
      overrides="${cfg.localOverrideFile}"

      if [ "$(id -u)" -ne 0 ]; then
        echo "easy-nix-powerwash must run as root" >&2
        exit 1
      fi

      answer=""
      if [ "''${1:-}" != "--yes" ]; then
        echo "This will erase:"
        echo "  - everything in /home/$user"
        echo "  - $overrides (your local customisations)"
        echo "  - local changes in $dir"
        printf 'Type POWERWASH to continue: '
        read -r answer
        if [ "$answer" != "POWERWASH" ]; then
          echo "cancelled"
          exit 1
        fi
      fi

      echo "==> removing local overrides"
      rm -f "$overrides"

      echo "==> resetting the configuration checkout"
      if [ -d "$dir/.git" ]; then
        git -C "$dir" reset --hard
        git -C "$dir" clean -fd
      else
        echo "    no checkout at $dir, skipping" >&2
      fi

      echo "==> emptying /home/$user"
      if id "$user" >/dev/null 2>&1; then
        # Deleting the directory itself would break the session that is running it;
        # empty it instead, then restore the skeleton.
        find "/home/$user" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
        cp -rT /etc/skel "/home/$user"
        chown -R "$user:" "/home/$user"
      fi

      echo "==> building the pristine system"
      nixos-rebuild boot --flake "$dir#$host" --no-write-lock-file

      ${notify}/bin/easy-nix-notify "easy-nix reset" "Reboot to start from a clean system."
      echo
      echo "Done. Reboot to start from a clean system."
    '';
  };
in
{
  config = lib.mkIf cfg.powerwash.enable {
    environment.systemPackages = [
      powerwash
      (pkgs.makeDesktopItem {
        name = "easy-nix-powerwash";
        desktopName = "Reset this computer";
        comment = "Erase personal data and restore the original system";
        icon = "edit-clear-all";
        categories = [ "System" ];
        exec = "${pkgs.foot}/bin/foot -e sudo ${powerwash}/bin/easy-nix-powerwash";
      })
    ];

    # A skeleton worth restoring: the reset has to produce a machine someone can use.
    environment.etc."skel/.config/easy-nix/README".text = ''
      easy-nix
      ========

      Machine-specific changes go in ${cfg.localOverrideFile}, not in
      ${cfg.configDir}: that directory is fast-forwarded from git on every update,
      and edits there block the update instead of being preserved.
    '';
  };
}
