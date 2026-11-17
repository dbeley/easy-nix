/*
  The appliance as installed on a disk. This is the system the ISO installs, and the
  one that self-updates.
*/
{
  ...
}:
{
  imports = [
    ../../modules/disk-layout.nix
    ../../modules/desktop/wayland.nix
    ../../modules/flatpak.nix
    ../../modules/apps/browsers.nix
    ../../modules/apps/office.nix
    ../../modules/apps/pi.nix
  ];

  easyNix = {
    enable = true;
    flakeRef = "https://github.com/dbeley/easy-nix.git";
  };
}
