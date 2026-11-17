/*
  Wayland desktop, system side.

  There is no X server in this system: `services.xserver.enable` is asserted false
  rather than merely left alone, because "Wayland only" is the point of the project and
  a dependency pulling X in would otherwise go unnoticed until a machine booted into it.
  Applications that need X (Steam, Chromium's older paths) go through
  `xwayland-satellite`, which is started on demand by niri.
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
in
{
  # Sessions are started from tty1 rather than by a display manager: one less daemon,
  # one less place to be broken, and no greeter for a single-user appliance.
  services.getty.autologinUser = lib.mkIf cfg.autologin user;

  environment.loginShellInit = lib.mkIf cfg.autologin ''
    # Only the first console, and only once.
    #
    # The second condition is not belt-and-braces. `niri-session` re-executes itself
    # through a *login* shell to pick up a clean login environment, and that login shell
    # sources this file again. Guarding on WAYLAND_DISPLAY alone - which is unset until
    # niri is already running - recursed instead: measured on the light image, the shell
    # re-execed once a second, `niri.service` never started, and the screen stayed on a
    # shell that drew nothing. An exported variable is the only thing that survives that
    # re-exec, since it is inherited across it.
    if [ -z "''${WAYLAND_DISPLAY:-}" ] &&
      [ -z "''${EASY_NIX_SESSION_LAUNCHED:-}" ] &&
      [ "$(tty)" = "/dev/tty1" ]; then
      export EASY_NIX_SESSION_LAUNCHED=1
      exec ${lib.getExe' pkgs.niri "niri-session"}
    fi
  '';

  # --- portals --------------------------------------------------------------
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-gnome
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
  environment.systemPackages = with pkgs; [
    niri
    foot # terminal: Wayland-native, no toolkit to pull in
    fuzzel # launcher
    mako # notifications
    swayidle
    swaylock # PAM-authenticated screen lock
    xwayland-satellite
    wl-clipboard
    brightnessctl
    playerctl
    grim
    slurp
    pcmanfm # file manager
    pavucontrol
    xwayland
  ];

  security.pam.services.swaylock = { };

  # --- fonts ----------------------------------------------------------------
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-color-emoji
      noto-fonts-cjk-sans
      dejavu_fonts
      liberation_ttf
      terminus_font
    ];
    fontconfig.defaultFonts = {
      sansSerif = [ "Noto Sans" ];
      monospace = [ "DejaVu Sans Mono" ];
    };
  };

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
