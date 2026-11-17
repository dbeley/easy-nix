/*
  The bootable installer.

  Same applications as an installed machine, plus the install tool, so the medium can be
  tried as a live system (wifi, screen, keyboard) before anything is written to disk.
*/
{
  ...
}:
{
  imports = [
    ../../modules/desktop/wayland.nix
    ../../modules/flatpak.nix
    ../../modules/apps/browsers.nix
    ../../modules/apps/office.nix
    ../../modules/apps/pi.nix
    ../../modules/installer
  ];

  easyNix = {
    enable = true;
    # A medium has no checkout to fast-forward and nothing to reset: the timers would
    # only produce a failed unit and a notification nobody can act on.
    update.enable = false;
    update.upgrade = false;
    powerwash.enable = false;
  };
}
