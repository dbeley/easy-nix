/*
  Self-update.

  Shape: the configuration is a git checkout that the machine fast-forwards, and a
  weekly timer builds the *next* generation without touching the running one. Nothing
  reboots on its own; the operator gets a notification and reboots when it suits.

  The two rules that make this safe, and that a naive implementation gets wrong:

    1. Fast-forward or nothing. If the checkout has local modifications, or has
       diverged from its remote, the update stops and says so. Never `reset --hard`:
       that turns "I edited a line at /etc/easy-nix" into silent data loss.
    2. `flake.lock` is bumped upstream, never on the machine. Every appliance runs the
       same pinned nixpkgs, so "it works on mine" is a statement about a revision and
       not about a moment. Machines stop writing their own lock file
       (`--no-write-lock-file`).

  Machine-specific customisation lives in `easyNix.localOverrideFile`, outside this
  checkout, and is imported at highest priority (`modules/easy-nix/overrides.nix`).
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
in
{
  config = lib.mkMerge [
    {
      # --- the override hook, imported when present ---------------------------
      # A path that does not exist cannot be imported, so this is assembled with
      # pathExists rather than `optionalAttrs` on the import list.
      imports = lib.optional (builtins.pathExists cfg.localOverrideFile) cfg.localOverrideFile;
    }

    (lib.mkIf cfg.update.enable {
      systemd.services.easy-nix-update-config = {
        description = "easy-nix: fast-forward the configuration and update Flatpaks";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          # Do not fight the user for the machine.
          CPUWeight = 20;
          IOWeight = 20;
          ExecStart = "${pkgs.writeShellApplication {
            name = "easy-nix-update-config";
            runtimeInputs = [
              pkgs.git
              pkgs.flatpak
              pkgs.coreutils
            ];
            text = ''
              dir="${cfg.configDir}"

              if [ ! -d "$dir/.git" ]; then
                echo "easy-nix: no git checkout at $dir" >&2
                exit 1
              fi

              if [ -n "$(git -C "$dir" status --porcelain)" ]; then
                echo "easy-nix: local modifications in $dir, refusing to update" >&2
                ${notify}/bin/easy-nix-notify \
                  "Update skipped" \
                  "$dir has local modifications. Nothing was overwritten."
                exit 1
              fi

              branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD)
              git -C "$dir" fetch --quiet origin

              if ! git -C "$dir" merge --ff-only "origin/$branch"; then
                echo "easy-nix: $dir cannot fast-forward from origin/$branch" >&2
                ${notify}/bin/easy-nix-notify \
                  "Update skipped" \
                  "$dir has diverged from its remote. Nothing was overwritten."
                exit 1
              fi

              # Flatpaks update themselves on their own cadence; if none are
              # installed this is a no-op rather than a failure.
              if flatpak list --system >/dev/null 2>&1; then
                flatpak update --noninteractive --assumeyes || true
              fi

              ${notify}/bin/easy-nix-notify \
                "Updates ready" \
                "Reboot when convenient to apply them."
            '';
          }}/bin/easy-nix-update-config";
        };
      };

      systemd.timers.easy-nix-update-config = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.update.configOnCalendar;
          Persistent = true;
          # Spread a fleet of machines over half an hour instead of hitting the
          # remote at the same minute.
          RandomizedDelaySec = "30m";
          Unit = "easy-nix-update-config.service";
        };
      };
    })

    (lib.mkIf cfg.update.upgrade {
      systemd.services.easy-nix-upgrade = {
        description = "easy-nix: build the next system generation";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          CPUWeight = 20;
          IOWeight = 20;
          # Fetch first; it fails loudly on the states the rebuild cannot handle, and
          # its notification already explains why.
          ExecStartPre = lib.mkIf cfg.update.enable "${notify}/bin/easy-nix-notify 'Update started' 'The new system is being built in the background.'";
          ExecStart = "${pkgs.writeShellApplication {
            name = "easy-nix-upgrade";
            runtimeInputs = [
              pkgs.nixos-rebuild
              pkgs.nix
              pkgs.coreutils
            ];
            text = ''
              dir="${cfg.configDir}"
              host="${config.networking.hostName}"

              if [ ! -d "$dir" ]; then
                echo "easy-nix: no configuration at $dir" >&2
                exit 1
              fi

              # boot, not switch: the running session is not replaced under the
              # operator's hands, and a broken generation is one reboot away from
              # being rolled back in the boot menu.
              nixos-rebuild boot --flake "$dir#$host" --no-write-lock-file

              ${notify}/bin/easy-nix-notify \
                "Update installed" \
                "Reboot to apply it. The previous version stays in the boot menu."
            '';
          }}/bin/easy-nix-upgrade";
        };
      };

      systemd.timers.easy-nix-upgrade = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.update.upgradeOnCalendar;
          Persistent = true;
          RandomizedDelaySec = "1h";
          Unit = "easy-nix-upgrade.service";
        };
      };
    })
  ];

  # Desktop launchers, so an update never requires a terminal. `Terminal = true` means
  # the operator watches the rebuild and can read an error it did not notify about.
  config.environment.systemPackages = lib.mkIf cfg.update.enable [
    (pkgs.makeDesktopItem {
      name = "easy-nix-update";
      desktopName = "Check for updates";
      comment = "Fetch configuration updates and rebuild the system";
      icon = "software-update-available";
      categories = [ "System" ];
      # niri has no concept of `Terminal=true`, so the terminal is named explicitly.
      # Without this the entry runs detached from any tty and the operator sees nothing.
      exec = "${pkgs.foot}/bin/foot -e sudo systemctl start easy-nix-update-config.service easy-nix-upgrade.service";
    })
  ];
}
