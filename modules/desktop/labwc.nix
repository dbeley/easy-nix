/*
  labwc and waybar, user side.

  labwc is a floating, stacking compositor on wlroots: Openbox's window model, on
  Wayland, with no X server anywhere. That is the point of choosing it - niri's
  scrollable tiling is elegant and unlike anything a person has used before, and this
  appliance is meant to feel like a computer rather than to teach a window model. Windows
  have titlebars, dragging one moves it, maximising fills the screen, alt-tab cycles.

  waybar is the other half of "familiar": a panel with the clock, the system tray, the
  network and the volume. It is the only new daemon this switch adds.

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
      wayland-utils
    ];
    text = builtins.readFile ../../nix/session-report.sh;
  };

  # Screen blanking, shellcheck'd at build time like every other script in `nix/`.
  dpms = pkgs.writeShellApplication {
    name = "easy-nix-dpms";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      wlopm
      wlr-randr
    ];
    text = builtins.readFile ../../nix/dpms.sh;
  };

  # `labwc` reads one file per concern. rc.xml is the Openbox configuration this
  # compositor deliberately kept compatible: keybinds, window rules, theme.
  rcXml = ''
    <?xml version="1.0"?>
    <labwc_config>
      <core>
        <gap>0</gap>
        <adaptiveSync>no</adaptiveSync>
      </core>
      <theme>
        <!-- From nixpkgs' `labwc-themes`, installed by modules/desktop/wayland.nix. -->
        <name>labAdwaita-dark</name>
        <cornerRadius>6</cornerRadius>
        <font place="ActiveWindow">
          <name>Noto Sans</name><size>10</size>
        </font>
        <font place="InactiveWindow">
          <name>Noto Sans</name><size>10</size>
        </font>
        <font place="MenuItem">
          <name>Noto Sans</name><size>10</size>
        </font>
        <font place="OnScreenDisplay">
          <name>Noto Sans</name><size>10</size>
        </font>
      </theme>
      <placement>
        <policy>cascade</policy>
      </placement>
      <focus>
        <followMouse>no</followMouse>
      </focus>
      <desktops>
        <number>4</number>
        <names>
          <name>one</name><name>two</name><name>three</name><name>four</name>
        </names>
      </desktops>
      <keyboard>
        <!-- Super is the modifier, as it was under niri, so muscle memory survives. -->
        <keybind key="W-Return">
          <action name="Execute" command="foot"/>
        </keybind>
        <keybind key="W-d">
          <action name="Execute" command="fuzzel"/>
        </keybind>
        <keybind key="W-e">
          <action name="Execute" command="pcmanfm"/>
        </keybind>
        <keybind key="W-q">
          <action name="Close"/>
        </keybind>
        <keybind key="W-f">
          <action name="ToggleMaximize"/>
        </keybind>
        <keybind key="W-S-f">
          <action name="ToggleFullscreen"/>
        </keybind>
        <keybind key="A-Tab">
          <action name="NextWindow"/>
        </keybind>
        <keybind key="W-Left">
          <action name="SnapToEdge" direction="left"/>
        </keybind>
        <keybind key="W-Right">
          <action name="SnapToEdge" direction="right"/>
        </keybind>
        <keybind key="W-Up">
          <action name="ToggleMaximize"/>
        </keybind>
        <keybind key="W-1">
          <action name="GoToDesktop" to="1"/>
        </keybind>
        <keybind key="W-2">
          <action name="GoToDesktop" to="2"/>
        </keybind>
        <keybind key="W-3">
          <action name="GoToDesktop" to="3"/>
        </keybind>
        <keybind key="W-4">
          <action name="GoToDesktop" to="4"/>
        </keybind>
        <keybind key="W-S-1">
          <action name="SendToDesktop" to="1"/>
        </keybind>
        <keybind key="W-S-2">
          <action name="SendToDesktop" to="2"/>
        </keybind>
        <keybind key="W-S-3">
          <action name="SendToDesktop" to="3"/>
        </keybind>
        <keybind key="W-S-4">
          <action name="SendToDesktop" to="4"/>
        </keybind>
        <keybind key="Print">
          <action name="Execute" command="sh -c 'mkdir -p &quot;$HOME/Pictures/Screenshots&quot; &amp;&amp; grim -g &quot;$(slurp)&quot; &quot;$HOME/Pictures/Screenshots/$(date +%F-%H%M%S).png&quot;'"/>
        </keybind>
        <keybind key="W-S-e">
          <action name="Exit"/>
        </keybind>
        <keybind key="W-S-p">
          <action name="Execute" command="poweroff"/>
        </keybind>
        <keybind key="W-S-o">
          <action name="Execute" command="reboot"/>
        </keybind>
      </keyboard>
      <mouse>
        <context name="Root">
          <mousebind button="Right" action="Press">
            <action name="ShowMenu" menu="root-menu"/>
          </mousebind>
        </context>
      </mouse>
    </labwc_config>
  '';

  # The desktop menu: what a person gets by right-clicking the background, which is the
  # one discoverable gesture an unfamiliar desktop has.
  menuXml = ''
    <?xml version="1.0"?>
    <openbox_menu>
      <menu id="root-menu" label="easy-nix">
        <item label="Terminal">
          <action name="Execute" command="foot"/>
        </item>
        <item label="Files">
          <action name="Execute" command="pcmanfm"/>
        </item>
        <item label="Applications">
          <action name="Execute" command="fuzzel"/>
        </item>
        <separator/>
        <item label="Reconfigure">
          <action name="Reconfigure"/>
        </item>
        <item label="Exit the session">
          <action name="Exit"/>
        </item>
      </menu>
    </openbox_menu>
  '';

  # labwc runs this file as a shell script once the compositor is up. Importing the
  # environment is what lets `graphical-session.target` hand the Wayland socket to the
  # user units: without it they start without WAYLAND_DISPLAY and every one of them
  # fails with "failed to connect to display".
  autostart = ''
    systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE
    # Not `start graphical-session.target`: systemd marks that target
    # RefuseManualStart=yes, because a session manager is supposed to pull it in, not to
    # start it. `easy-nix-session.service` exists only to Want it, which is a dependency
    # request rather than a manual start - measured: the direct call is refused with
    # "may be requested by dependency only", and every unit below then never ran.
    systemctl --user start --no-block easy-nix-session.service
  '';

  # A panel with the clock on the left and the useful indicators on the right, and
  # nothing that needs a script of its own: every module below is built into waybar.
  waybarConfig = {
    layer = "top";
    position = "top";
    height = 30;
    spacing = 8;
    "modules-left" = [ "clock" ];
    "modules-right" = [
      "network"
      "pulseaudio"
      "battery"
      "tray"
    ];
    clock = {
      format = "{:%a %d %b  %H:%M}";
      "tooltip-format" = "{:%A %d %B %Y}";
    };
    network = {
      "format-wifi" = "  {essid}";
      "format-ethernet" = "  {ifname}";
      "format-disconnected" = "  offline";
      "tooltip-format" = "{ipaddr}/{cidr}";
      "on-click" = "foot -e nmtui";
    };
    pulseaudio = {
      format = "{icon}  {volume}%";
      "format-muted" = " muted";
      "format-icons" = {
        default = [
          ""
          ""
          ""
        ];
      };
      "on-click" = "pavucontrol";
    };
    battery = {
      states = {
        warning = 30;
        critical = 15;
      };
      format = "{icon}  {capacity}%";
      "format-icons" = [
        ""
        ""
        ""
        ""
        ""
      ];
    };
    tray = {
      spacing = 6;
    };
  };

  # Dark, high contrast, one accent: the same blue the niri border used, so the
  # wallpaper and the panel do not disagree about what the theme is.
  waybarStyle = ''
    * {
      font-family: "Noto Sans", sans-serif;
      font-size: 12px;
      border: none;
      border-radius: 0;
      min-height: 0;
    }

    window#waybar {
      background: #1e1e2e;
      color: #cdd6f4;
    }

    #clock, #network, #pulseaudio, #battery, #tray {
      padding: 0 10px;
      margin: 0;
    }

    #clock {
      color: #7aa2f7;
      font-weight: bold;
    }

    #battery.warning {
      color: #e0af68;
    }

    #battery.critical {
      color: #f7768e;
    }

    #network.disconnected {
      color: #f7768e;
    }
  '';
in
{
  xdg.configFile."labwc/rc.xml".text = rcXml;
  xdg.configFile."labwc/menu.xml".text = menuXml;
  xdg.configFile."labwc/autostart" = {
    text = autostart;
    executable = true;
  };
  xdg.configFile."waybar/config".text = builtins.toJSON waybarConfig;
  xdg.configFile."waybar/style.css".text = waybarStyle;

  # Session services. Bound to graphical-session.target, which the autostart script
  # above brings up.
  # A unit whose only job is to Want `graphical-session.target`: systemd refuses a
  # manual start of that target, so the session's autostart starts *this* and the target
  # comes up as its dependency.
  systemd.user.services.easy-nix-session = {
    Unit = {
      Description = "Pull up graphical-session.target";
      Wants = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/true";
    };
  };

  systemd.user.services.waybar = {
    Unit = {
      Description = "Panel: clock, tray, network, volume";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${lib.getExe pkgs.waybar}";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

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
      # No lock screen, and no password to unlock one with: see
      # `easyNix.user.initialPassword`, which defaults to null. `wlopm` is the output
      # power management client every wlroots compositor speaks; labwc included.
      ExecStart = "${pkgs.swayidle}/bin/swayidle -w timeout 600 '${lib.getExe dpms} off' resume '${lib.getExe dpms} on'";
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
