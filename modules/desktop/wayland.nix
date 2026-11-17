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

  # From the NixOS artwork set, so the file ships with the distribution and its licence
  # allows it. Neutral on purpose: a wallpaper that clashes with the applications a user
  # installs later is worse than a plain one, and a 2560x1440 gradient scales to any
  # display without looking stretched.
  wallpaper = "${
    pkgs.nixos-artwork.wallpapers."gradient-grey"
  }/share/wallpapers/gradient-grey/contents/images/2560x1440.png";
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

  # --- graphics -------------------------------------------------------------
  # `/run/opengl-driver` is not about 3D quality: niri's TTY backend looks for a render
  # node and a working EGL/GBM driver before it will drive an output, and it skips
  # software renderers on purpose ("software EGL renderers are skipped"). Without this,
  # the compositor starts, listens on its socket, answers `niri msg` - and reports
  # `outputs=0`, on a screen that never changes.
  #
  # It belongs here and not in `modules/apps/steam.nix`, where it was: Steam is x86-only,
  # so the aarch64 flavour - which has a desktop and no Steam - was left with no renderer
  # at all. Measured on the light image before the move: same `outputs=0`.
  hardware.graphics.enable = true;

  # The compositor falls back to a theme called `default` when nothing says otherwise,
  # and this system installs no such theme: `WARN niri::cursor: error loading xcursor
  # default@24: no default icon`, which is the oversized pointer. Name one that exists.
  environment.sessionVariables = {
    XCURSOR_THEME = "Adwaita";
    XCURSOR_SIZE = "24";
  };

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
    swaybg # draws the wallpaper: a compositor has no background of its own
    xwayland-satellite
    wl-clipboard
    brightnessctl
    playerctl
    grim
    slurp
    pcmanfm # file manager
    pavucontrol
    xwayland
    # A cursor theme has to exist on disk: the compositor's fallback is a theme named
    # `default` that nothing here provides, which draws the oversized pointer. Named by
    # `XCURSOR_THEME` above.
    adwaita-icon-theme
  ];

  # No lock screen, and no password for the account (see `easyNix.user.initialPassword`,
  # which defaults to null). A lock screen over an account with no password is a button
  # that cannot be pressed: `swaylock` asks PAM for a secret that does not exist, and the
  # only way out is a reboot.

  # --- wallpaper ------------------------------------------------------------
  # Without this the desktop is a black screen that is indistinguishable from a failed
  # boot. A user unit rather than a line in the compositor's config, so that replacing
  # the compositor does not mean rediscovering the wallpaper.
  systemd.user.services.easy-nix-wallpaper = {
    description = "Draw the desktop background";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.swaybg}/bin/swaybg --mode fill --image ${wallpaper}";
      Restart = "on-failure";
    };
  };

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
