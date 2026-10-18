/*
  A deliberately light live image, existing only so a boot test can run somewhere the
  full image cannot be built or booted (a 2-core VM, a CI runner without much disk).

  It proves that the live medium reaches userspace and that the Wayland session comes
  up. It proves nothing about the applications, because it does not contain them - the
  release workflow boots the real image for that.
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
    # No update services on a medium: there is nothing to update, and the timers would
    # fire during the boot test and slow it down.
    update.enable = false;
    update.upgrade = false;
    powerwash.enable = false;
  };
}
