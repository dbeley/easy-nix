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

  easyNix.enable = true;
}
