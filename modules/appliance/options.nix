/*
  Options for the appliance layer. Everything the self-update and reset machinery
  needs is declared here so a host can turn a piece off without editing the
  services themselves.
*/
{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    mkOption
    types
    ;

  inherit (config) easyNix;
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

        This file is imported at the highest priority and is **never** written or
        reset by anything in this repository. It is the deliberate answer to the
        failure mode of a git-driven distribution: an update that overwrites local
        customisation. Powerwash is the only thing that removes it, and it says so
        before doing it.
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
      default = "easy-nix";
      description = ''
        Initial password for the desktop user, applied only while the account has
        no password yet. Set to null to leave the account locked and hash your own.
        Change it at first boot: `passwd`.
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

  config = {
    warnings =
      lib.optional
        (!easyNix.enable && (easyNix.update.enable || easyNix.update.upgrade || easyNix.powerwash.enable))
        "easy-nix: easyNix.enable is false, so the update and powerwash services will run without the override hook being documented to the user.";
  };
}
