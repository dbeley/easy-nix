/*
  The bootable installer.

  Same applications as an installed machine, plus the install tool — so the medium can
  be used as a live system to check the machine works (wifi, screen, keyboard) before
  anything is written to disk. That is cheap insurance on the hardware this project
  targets.
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
    ../../modules/apps/steam.nix
    ../../modules/apps/opencode.nix
    ../../modules/installer
  ];

  easyNix = {
    enable = true;
    # A live medium has no configuration checkout to fast-forward and nothing worth
    # resetting: the installer creates both on the target. Leaving the timers on would
    # only produce a failed unit and a notification nobody can act on.
    update.enable = false;
    update.upgrade = false;
    powerwash.enable = false;
  };
}
