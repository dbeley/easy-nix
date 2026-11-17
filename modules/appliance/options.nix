/*
  Options for the appliance layer. Everything the self-update and reset machinery
  needs is declared here so a host can turn a piece off without editing the
  services themselves.
*/
{ lib, ... }:
let
  inherit (lib)
    mkOption
    types
    ;
in
{
  options.easyNix = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether this machine is an easy-nix appliance: self-updating from a git
        checkout of the configuration, and resettable in one command.
      '';
    };

    flakeRef = mkOption {
      type = types.str;
      default = "https://github.com/dbeley/easy-nix.git";
      example = "https://github.com/someone/easy-nix.git";
      description = ''
        Git remote the appliance follows. Only used to *create* the checkout on a
        fresh install; after that the checkout's own remote is authoritative.
      '';
    };

    autoInstall = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/dev/vda";
      description = ''
        Install onto this whole block device at boot, without a prompt and without a
        screen, then power off. `null` disables it.

        It exists so the install path can be exercised by a machine instead of by a
        remembered procedure. Nothing that ships sets it: a medium that installed
        itself over whatever disk was attached is not one to hand out.
      '';
    };

    configDir = mkOption {
      type = types.path;
      default = "/etc/easy-nix";
      readOnly = true;
      description = ''
        Where the configuration checkout lives. The update service fast-forwards
        this directory and nothing else.
      '';
    };

    localOverrideFile = mkOption {
      type = types.path;
      default = "/etc/easy-nix-local.nix";
      readOnly = true;
      description = ''
        Path to the machine's own overrides, if the operator created one.

        Imported at the highest priority and **never** written or reset by anything in
        this repository - the deliberate answer to a git-driven distribution silently
        overwriting local customisation. Powerwash is the only thing that removes it,
        and it says so first.
      '';
    };

    autologin = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Log the desktop session in automatically on tty1. On by default: an
        appliance that asks for a password before doing anything is not one.
      '';
    };

    user.initialPassword = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Password for the desktop user. Null by default because it would protect
        nothing: the session logs itself in, and `sudo` in `wheel` does not ask. A
        value here only makes a lock screen possible, and there is none.

        Set a string if you want one. It is applied only while the account has no
        password yet, so `passwd` has the last word.
      '';
    };

    update = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Fetch configuration updates and update Flatpaks daily.";
      };

      upgrade = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Build the next system generation weekly and make it the boot default.
          The running system is untouched until the machine is rebooted.
        '';
      };

      configOnCalendar = mkOption {
        type = types.str;
        default = "daily";
        example = "Tue..Sun 03:00";
        description = "systemd calendar spec for the configuration fetch.";
      };

      upgradeOnCalendar = mkOption {
        type = types.str;
        default = "Mon 04:00";
        example = "weekly";
        description = "systemd calendar spec for building the next generation.";
      };
    };

    powerwash = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Install the `easy-nix-powerwash` command and its desktop entry: wipes
          user data, the local overrides and the configuration checkout, then
          reinstalls a pristine system.
        '';
      };
    };
  };
}
