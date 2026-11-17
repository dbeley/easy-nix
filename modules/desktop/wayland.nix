/*
  Wayland desktop, system side.

  There is no X server in this system: `services.xserver.enable` is asserted false
  rather than merely left alone, because "Wayland only" is the point of the project and
  a dependency pulling X in would otherwise go unnoticed until a machine booted into it.
  An application that needs X goes through Xwayland, which `programs.labwc` starts.
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

  # `labwc-themes` is not in nixpkgs, and the compositor's own default is the 2005-looking
  # Openbox Clearlooks theme. `labAdwaita-dark` matches the panel and the wallpaper.
  # Pinned by revision: an image that rebuilds nightly off a moving branch changes its
  # desktop without anybody deciding it should.
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
in
{
  # Sessions are started from tty1 rather than by a display manager: one less daemon,
  # one less place to be broken, and no greeter for a single-user appliance.
  services.getty.autologinUser = lib.mkIf cfg.autologin user;

  environment.loginShellInit = lib.mkIf cfg.autologin ''
    # Only on the first console, and only once. Anything that opens a login shell on
    # this tty re-sources this file, so the guard cannot be `WAYLAND_DISPLAY` alone: the
    # exported flag is what survives the re-source.
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
  # A compositor wants a render node and an EGL/GBM driver before it drives an output;
  # without them labwc falls back to pixman, draws slowly, and the boot test's output
  # assertion finds nothing. It lives here rather than in an application module because
  # the aarch64 flavour has a desktop too.
  hardware.graphics.enable = true;

  # What a graphical desktop pulls in by default, and this image does not want.
  #
  # `services/misc/graphical-desktop.nix` sets `services.speechd.enable` to
  # `mkDefault true`, and speech-dispatcher carries mbrola plus the mbrola voice set:
  # 644 MiB of voices and a second speech engine, for a screen reader this image does
  # not ship. Attributed with `nix why-depends --all` on the appliance closure, where
  # the path ran system-path -> speech-dispatcher -> mbrola -> mbrola-voices. Removing
  # the GNOME portal did not touch it, which is what that measurement was for.
  services.speechd.enable = false;

  # The compositor's fallback cursor theme is called `default`, which nothing here
  # installs - that is the oversized pointer. The keyboard layout is read from the
  # environment, not from a compositor config file.
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
  # `xdg.portal` puts `/share/xdg-desktop-portal` on `pathsToLink` itself, so the module
  # owns the plumbing and this only names the implementation.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = lib.mkDefault "gtk";
  };

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

  # --- wallpaper --------------------------------------------------------------
  # `swaybg` and nothing else. It draws an image on the output and has no other job,
  # which is exactly what this needs.
  #
  # `pcmanfm --desktop` was here instead, to get desktop icons and a settings dialog
  # with them. Measured on a real Wayland session - headless labwc, pixman, no DISPLAY -
  # it dies with SIGSEGV before it starts: exit 139, no desktop manager, therefore no
  # wallpaper, and "Desktop manager is not active." from every entry that asks one for
  # its settings. That dialog was not a separate bug; it was the corpse.
  #
  # Under X11 the same command works, which is why the temptation to "just verify it"
  # is a trap: a probe that inherits DISPLAY is testing the host's X server, not this
  # session. The desktop-preferences entry is hidden in `modules/desktop/labwc.nix`
  # rather than left to pop that dialog.
  systemd.user.services.easy-nix-wallpaper = {
    description = "Wallpaper";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.swaybg} -i ${wallpaper} -m fill";
      Restart = "on-failure";
    };
  };

  # --- the VM a developer boots ---------------------------------------------
  #
  # `just run-vm` builds nixpkgs' `system.build.vm`, whose runner leaves QEMU on default
  # `-vga std` - a bochs card mesa has no driver for - so the device is named here. 2D
  # virtio, not virgl, for the same reason as `just run-iso`: on the GL path a virgl
  # guest renders the pointer inverted.
  #
  # `vmVariant` and not `virtualisation.*`: since nixpkgs split `build-vm` out, the QEMU
  # options live in the nested configuration that produces the runner.
  virtualisation.vmVariant.virtualisation.qemu.options = [
    "-device virtio-vga"
    "-display gtk"
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
