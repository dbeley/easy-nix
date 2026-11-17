/*
  Wayland desktop, system side.

  There is no X server in this system: `services.xserver.enable` is asserted false
  rather than merely left alone, because "Wayland only" is the point of the project and
  a dependency pulling X in would otherwise go unnoticed until a machine booted into it.
  Applications that need X (Steam, Chromium's older paths) go through Xwayland, which
  `programs.labwc` starts for us; there is no X server for them to talk to directly.
*/
{
  config,
  lib,
  pkgs,
  user,
  ...
}:
let
  cfg = config.easyNix;

  # From the NixOS artwork set, so the file ships with the distribution and its licence
  # allows it. Neutral on purpose: a wallpaper that clashes with the applications a user
  # installs later is worse than a plain one, and a 2560x1440 gradient scales to any
  # display without looking stretched.
  wallpaper = "${
    pkgs.nixos-artwork.wallpapers."gradient-grey"
  }/share/wallpapers/gradient-grey/contents/images/2560x1440.png";

  # `labwc-themes` is not in nixpkgs, and the compositor's own default is the Openbox
  # Clearlooks theme, which looks like 2005. `labAdwaita-dark` is the theme the labwc
  # project ships for exactly this: an Adwaita-shaped dark titlebar that matches the
  # panel and the wallpapers that come with the distribution.
  #
  # Pinned by revision rather than tracked: an image that rebuilds itself nightly off a
  # moving branch is an image whose desktop changes without anybody deciding it should.
  labwcThemes = pkgs.stdenvNoCC.mkDerivation {
    pname = "labwc-themes";
    version = "6a2e363";
    src = pkgs.fetchFromGitHub {
      owner = "labwc";
      repo = "labwc-themes";
      rev = "6a2e3634eef03e7f124359ad28ed5da2d931f96d";
      hash = "sha256-5kCYm3qo7TQif/9aTViDozX/AO+kfoiipTJfPIBcu3g=";
    };
    # The theme is a directory of XML and PNGs: no build, just a copy. Upstream's
    # Makefile runs meson, which is a build system this derivation does not have.
    dontBuild = true;
    dontConfigure = true;
    installPhase = ''
      mkdir -p $out/share/themes
      cp -r labAdwaita-dark "$out/share/themes/"
    '';
  };
  # One script rather than a shell line in the unit: the wallpaper path and the mode are
  # arguments, and a unit file is not the place to discover that they were mis-quoted.
  desktopManager = pkgs.writeShellApplication {
    name = "easy-nix-desktop";
    runtimeInputs = [ pkgs.pcmanfm ];
    text = ''
      pcmanfm --set-wallpaper ${wallpaper} --wallpaper-mode=fit
      exec pcmanfm --desktop
    '';
  };
in
{
  # Sessions are started from tty1 rather than by a display manager: one less daemon,
  # one less place to be broken, and no greeter for a single-user appliance.
  services.getty.autologinUser = lib.mkIf cfg.autologin user;

  environment.loginShellInit = lib.mkIf cfg.autologin ''
    # Only the first console, and only once.
    #
    # Both conditions are needed. `WAYLAND_DISPLAY` alone would be enough for a
    # compositor that never re-sources this file, but the login shell is sourced again by
    # anything that opens a login shell on this tty - and the guard has to survive that.
    # The exported variable is inherited across it, which is the only reason it works.
    #
    # This was measured, not imagined: with `niri-session`, which re-executes itself
    # through a login shell, guarding on display alone re-execed the launcher once a
    # second and the desktop never started.
    if [ -z "''${WAYLAND_DISPLAY:-}" ] &&
      [ -z "''${EASY_NIX_SESSION_LAUNCHED:-}" ] &&
      [ "$(tty)" = "/dev/tty1" ]; then
      export EASY_NIX_SESSION_LAUNCHED=1
      # labwc started by hand does not declare the session the way a session manager
      # would, and `nix/session-report.sh` reports these two rather than inventing them.
      export XDG_SESSION_TYPE=wayland
      export XDG_CURRENT_DESKTOP=labwc
      exec ${lib.getExe pkgs.labwc}
    fi
  '';

  # --- graphics -------------------------------------------------------------
  # `/run/opengl-driver` is not about 3D quality: a compositor looks for a render node
  # and a working EGL/GBM driver before it will drive an output, and niri - the previous
  # choice - skipped software renderers on purpose ("software EGL renderers are
  # skipped"), so it started, listened on its socket, answered its own IPC and reported
  # `outputs=0` on a screen that never changed. labwc, on wlroots, would fall back to
  # pixman and draw; the driver is still what makes it draw at a usable speed, and it is
  # what the boot test's output assertion exercises.
  #
  # It belongs here and not in `modules/apps/steam.nix`, where it was: Steam is x86-only,
  # so the aarch64 flavour - which has a desktop and no Steam - was left with no renderer
  # at all. Measured on the light image before the move: same `outputs=0`.
  hardware.graphics.enable = true;

  # The compositor falls back to a theme called `default` when nothing says otherwise,
  # and this system installs no such theme: `error loading xcursor default@24: no
  # default icon`, which is the oversized pointer. Name one that exists. Same for the
  # keyboard: niri used to carry `layout = "fr"` in its own config, and wlroots reads the
  # layout from these instead, so the French AZERTY layout outlives the compositor.
  environment.sessionVariables = {
    XCURSOR_THEME = "Adwaita";
    XCURSOR_SIZE = "24";
    XKB_DEFAULT_LAYOUT = "fr";
    XKB_DEFAULT_VARIANT = "oss";
  };

  # The session itself: the package, the desktop entry, the portals, and Xwayland. This
  # is the supported path - doing it by hand is how `xdg.portal` ends up silently
  # incomplete for every application that asks for the screen or the clipboard.
  programs.labwc.enable = true;

  # --- portals --------------------------------------------------------------
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      # gnome portal removed: labwc + gtk/wlr portals are what the session uses
    ];
    config.common.default = lib.mkDefault "gtk";
  };

  # home-manager's niri module links portal definitions; without this the portals it
  # installs are invisible to the session.
  environment.pathsToLink = [ "/share/xdg-desktop-portal" ];

  # --- secrets --------------------------------------------------------------
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;

  # --- session utilities ----------------------------------------------------
  #
  # labwc and waybar come from `programs.labwc` below (which also gives the session its
  # Xwayland); only what it does not cover is listed here.
  environment.systemPackages = with pkgs; [
    foot # terminal: Wayland-native, no toolkit to pull in
    fuzzel # launcher
    mako # notifications
    swayidle
    wlopm # output power management, for `swayidle`
    labwc-tweaks # GUI for rc.xml: theme, fonts, keybinds
    labwc-menu-generator # writes menu.xml from the XDG .desktop files
    wayland-utils # `wayland-info`: what the session report asks its questions with
    wl-clipboard
    brightnessctl
    playerctl
    grim
    slurp
    pcmanfm # file manager
    pavucontrol
    # A cursor theme has to exist on disk: the compositor's fallback is a theme named
    # `default` that nothing here provides, which draws the oversized pointer. Named by
    # `XCURSOR_THEME` above.
    adwaita-icon-theme
    labwcThemes
  ];

  # No lock screen, and no password for the account (see `easyNix.user.initialPassword`,
  # which defaults to null). A lock screen over an account with no password is a button
  # that cannot be pressed: `swaylock` asks PAM for a secret that does not exist, and the
  # only way out is a reboot.

  # --- wallpaper and the desktop ---------------------------------------------
  # `pcmanfm --desktop` is the desktop manager: it draws the wallpaper and the icons,
  # and it is what the "Desktop Preferences" entry in the menus talks to. `swaybg` drew
  # a background and nothing else, so that dialog answered "the desktop manager is not
  # running" - measured, on a booted image, and a menu entry that cannot work is worse
  # than no entry.
  #
  # `--set-wallpaper` writes the image into pcmanfm's own configuration and applies it in
  # the same call, so a fresh account gets a wallpaper instead of a first-run dialog.
  systemd.user.services.easy-nix-desktop = {
    description = "Desktop manager: wallpaper and desktop icons";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = lib.getExe desktopManager;
      Restart = "on-failure";
    };
  };

  # --- the VM a developer boots ---------------------------------------------
  #
  # `just run-vm` builds nixpkgs' `system.build.vm`, whose runner leaves QEMU on its
  # default VGA: a bochs card mesa has no driver for. niri skips software EGL renderers,
  # so the compositor starts headless and the window shows the boot messages forever -
  # the desktop never appears, and nothing in it says why. virgl gives the guest a
  # renderer niri accepts.
  #
  # `vmVariant` and not `virtualisation.*` directly: since nixpkgs split `build-vm` out,
  # the QEMU options live in the nested configuration that produces the runner.
  virtualisation.vmVariant.virtualisation.qemu.options = [
    "-device virtio-vga-gl"
    "-display gtk,gl=on"
  ];

  assertions = [
    {
      assertion = !config.services.xserver.enable;
      message = ''
        easy-nix is Wayland-only: services.xserver.enable must stay false.
        An application that requires an X server has to run through XWayland
        (xwayland-satellite) instead of dragging X into the system.
      '';
    }
  ];
}
