/*
  niri configuration, user side (home-manager).

  Kept small on purpose. Anything that can be a systemd user unit is one (mako,
  swayidle) rather than a line in the compositor's config: a service that crashes is
  restarted, a spawned process is not.
*/
{
  lib,
  pkgs,
  config,
  ...
}:
let
  # The session's own report, packaged like the scripts in `nix/`: runtime dependencies
  # on PATH, and shellcheck run over the text at build time. It is only ever started by
  # the session, so it has no business in `environment.systemPackages`.
  sessionReport = pkgs.writeShellApplication {
    name = "easy-nix-session-report";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      niri
    ];
    text = builtins.readFile ../../nix/session-report.sh;
  };
in
{
  wayland.windowManager.niri = {
    enable = true;
    package = pkgs.niri;
    settings = {
      input = {
        keyboard = {
          repeat-delay = 200;
          repeat-rate = 60;
          xkb = {
            layout = "fr";
            variant = "oss";
          };
        };
        touchpad = {
          tap = [ ];
          "natural-scroll" = [ ];
          "click-method" = "clickfinger";
        };
        "focus-follows-mouse" = [ ];
      };

      cursor.hide-after-inactive-ms = 5000;

      layout = {
        gaps = 12;
        "focus-ring"."off" = [ ];
        border = {
          "on" = [ ];
          width = 4;
          "active-color" = "#7aa2f7";
          "inactive-color" = "#3b4261";
        };
        "preset-column-widths"._children = [
          { proportion = 1.0 / 2.0; }
          { proportion = 1.0 / 3.0; }
          { proportion = 2.0 / 3.0; }
        ];
        "preset-window-heights"._children = [
          { proportion = 1.0 / 2.0; }
          { proportion = 2.0 / 3.0; }
        ];
      };

      "prefer-no-csd" = true;
      "hotkey-overlay"."skip-at-startup" = [ ];
      screenshot-path = "~/Pictures/Screenshots/%Y-%m-%d %H-%M-%S.png";

      binds = {
        "Mod+Return".spawn = [ "foot" ];
        "Mod+D".spawn = [ "fuzzel" ];
        "Mod+Q".close-window = [ ];
        "Mod+Shift+E".quit = [ ];
        "Mod+Shift+P".spawn = [ "poweroff" ];
        "Mod+Shift+O".spawn = [ "reboot" ];

        "Mod+Left".focus-column-left = [ ];
        "Mod+Right".focus-column-right = [ ];
        "Mod+Up".focus-window-up = [ ];
        "Mod+Down".focus-window-down = [ ];

        "Mod+1".focus-workspace = 1;
        "Mod+2".focus-workspace = 2;
        "Mod+3".focus-workspace = 3;
        "Mod+4".focus-workspace = 4;
        "Mod+5".focus-workspace = 5;
        "Mod+6".focus-workspace = 6;
        "Mod+7".focus-workspace = 7;
        "Mod+8".focus-workspace = 8;
        "Mod+9".focus-workspace = 9;

        "Mod+Shift+1".move-column-to-workspace = 1;
        "Mod+Shift+2".move-column-to-workspace = 2;
        "Mod+Shift+3".move-column-to-workspace = 3;

        "Mod+Comma".consume-window-into-column = [ ];
        "Mod+Period".expel-window-from-column = [ ];
        "Mod+Minus".set-column-width = "-10%";
        "Mod+Plus".set-column-width = "+10%";

        "Print".screenshot = [ ];
        "Mod+Print".screenshot-window = [ ];
      };
    };
  };

  # Session services. Bound to graphical-session.target, which niri-session brings up.
  systemd.user.services.mako = {
    Unit = {
      Description = "mako notification daemon";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.mako}/bin/mako";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.swayidle = {
    Unit = {
      Description = "Blank the screen when idle";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      # Blanks the output after ten minutes and restores it on activity. No lock: the
      # account has no password, so `swaylock` could only ever ask for something that
      # does not exist - the screen would go dark and stay dark until a reboot.
      ExecStart = "${pkgs.swayidle}/bin/swayidle -w timeout 600 'niri msg action power-off-monitors' resume 'niri msg action power-on-monitors'";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.easy-nix-session-report = {
    Unit = {
      Description = "Announce on the serial console that the Wayland session is up";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      # `oneshot` and not a daemon: it prints one line and has nothing left to do. A
      # failing exit status is left alone rather than hidden, so a session that cannot
      # reach its own compositor says so in `systemctl --user status`.
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = lib.getExe sessionReport;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  xdg.userDirs = {
    enable = true;
    # Pinned to the value home-state-version 25.11 implies: the default flips at 26.05,
    # and a silent flip changes what `$XDG_DESKTOP_DIR` means to everything started from
    # the session. The directories themselves are written to ~/.config/user-dirs.dirs,
    # which is where the applications that care read them.
    setSessionVariables = true;
    createDirectories = true;
    desktop = "${config.home.homeDirectory}/Desktop";
    documents = "${config.home.homeDirectory}/Documents";
    download = "${config.home.homeDirectory}/Downloads";
    pictures = "${config.home.homeDirectory}/Pictures";
    videos = "${config.home.homeDirectory}/Videos";
    music = "${config.home.homeDirectory}/Music";
    templates = "${config.home.homeDirectory}/Templates";
    publicShare = "${config.home.homeDirectory}/Public";
  };
}
