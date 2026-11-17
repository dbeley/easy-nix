/*
  Self-update.

  The configuration is a git checkout the machine fast-forwards; a weekly timer builds
  the *next* generation without touching the running one. Nothing reboots on its own -
  the operator is notified and reboots when it suits.

  Two rules make this safe:

    1. Fast-forward or nothing. Local modifications or a diverged checkout stop the
       update and say why. Never `reset --hard`: that turns "I edited a line at
       /etc/easy-nix" into silent data loss.
    2. `flake.lock` moves upstream, never on the machine (`--no-write-lock-file`), so
       every appliance built from the same ISO runs the same pinned nixpkgs.

  systemd enforces the ordering rather than hope: the upgrade service runs the fetch as
  an `ExecStartPre`, so it never builds a configuration older than the remote, and a
  refusing fetch stops the rebuild with the notification that explains it. Machine
  customisation lives outside the checkout, in `easyNix.localOverrideFile`.
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

  # A literal rather than `cfg.localOverrideFile`: `imports` is resolved while the module
  # graph is still being assembled, so reading an option there risks recursion. The
  # warning below fires if the two ever differ.
  localOverrideFile = "/etc/easy-nix-local.nix";

  # Fast-forward the configuration, then update Flatpaks. Everything that can refuse
  # refuses here, loudly, without touching the operator's work.
  updateConfig = pkgs.writeShellApplication {
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

      # Flatpaks update themselves on their own cadence; if none are installed this is a
      # no-op rather than a failure.
      if flatpak list --system >/dev/null 2>&1; then
        flatpak update --noninteractive --assumeyes || true
      fi
    '';
  };

  # Build the next generation. Does not touch the running system.
  upgrade = pkgs.writeShellApplication {
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

      ${notify}/bin/easy-nix-notify \
        "Update started" \
        "The new system is being built in the background. You can keep working."

      # boot, not switch: the running session is not replaced under the operator's
      # hands, and a broken generation is one reboot away from being rolled back in
      # the boot menu.
      nixos-rebuild boot --flake "$dir#$host" --no-write-lock-file

      ${notify}/bin/easy-nix-notify \
        "Update installed" \
        "Reboot to apply it. The previous version stays in the boot menu."
    '';
  };
in
{
  # The override hook. A path that does not exist cannot be imported, so the import list
  # is conditional rather than the file being optional.
  imports = lib.optional (builtins.pathExists localOverrideFile) localOverrideFile;

  config = lib.mkMerge [
    {
      warnings =
        lib.optional (cfg.localOverrideFile != localOverrideFile) ''
          easy-nix: easyNix.localOverrideFile is ${cfg.localOverrideFile}, but the path
          imported at build time is fixed to ${localOverrideFile}. The override file will
          not be read.
        ''
        ++ lib.optional (
          !cfg.enable && (cfg.update.enable || cfg.update.upgrade)
        ) "easy-nix: easyNix.enable is false, so the update services are disabled.";
    }

    (lib.mkIf (cfg.enable && cfg.update.enable) {
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
          ExecStart = lib.getExe updateConfig;
        };
      };

      systemd.timers.easy-nix-update-config = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.update.configOnCalendar;
          Persistent = true;
          # Spread a fleet of machines over half an hour instead of hitting the remote
          # at the same minute.
          RandomizedDelaySec = "30m";
          Unit = "easy-nix-update-config.service";
        };
      };
    })

    (lib.mkIf (cfg.enable && cfg.update.upgrade) {
      systemd.services.easy-nix-upgrade = {
        description = "easy-nix: build the next system generation";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          CPUWeight = 20;
          IOWeight = 20;
          # Fetch before building, so the generation is the one the remote has now. If
          # the fetch refuses (local modifications, divergence) it has already notified
          # the operator, and there is nothing sensible left to build.
          ExecStartPre = lib.mkIf cfg.update.enable (lib.getExe updateConfig);
          ExecStart = lib.getExe upgrade;
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

    # A desktop launcher, so an update never requires a terminal. It starts the upgrade
    # service alone: that service fetches first, so asking for two units here would race
    # and could rebuild a configuration the fetch had not reached yet.
    #
    # The terminal is named explicitly because a Wayland compositor has no concept of `Terminal=true`:
    # an entry that prompts would otherwise run detached from any tty and the operator
    # would see nothing at all.
    (lib.mkIf (cfg.enable && cfg.update.upgrade) {
      environment.systemPackages = [
        (pkgs.makeDesktopItem {
          name = "easy-nix-update";
          desktopName = "Check for updates";
          comment = "Fetch configuration updates and rebuild the system";
          icon = "software-update-available";
          categories = [ "System" ];
          exec = "${pkgs.foot}/bin/foot -e sudo systemctl start easy-nix-upgrade.service";
        })
      ];
    })
  ];
}
