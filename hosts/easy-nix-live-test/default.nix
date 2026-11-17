/*
  A deliberately light live image: it exists only so a boot test can run where the full
  image cannot be built or booted (a 2-core VM, a CI runner without much disk).

  It proves the live medium reaches userspace and the Wayland session comes up. It proves
  nothing about the applications, because it does not contain them.
*/
{
  ...
}:
{
  imports = [
    ../../modules/desktop/wayland.nix
    ../../modules/installer/live.nix
  ];

  easyNix = {
    enable = true;
    # Nothing to update on a medium, and the timers would fire during the boot test.
    update.enable = false;
    update.upgrade = false;
    powerwash.enable = false;
  };
}
