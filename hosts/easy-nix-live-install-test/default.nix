/*
  The medium the install test boots: the light live image, plus the installer, plus an
  unattended install onto the disk the test attaches.

  It is light for the same reason `easy-nix-live-test` is: it has to build and boot on a
  runner, and it exists to exercise the installer, not the applications. The closure of
  the system it installs therefore comes from the binary cache rather than from the
  medium, which is the one difference from the released image - and the release
  workflow boot-tests that one.
*/
{
  ...
}:
{
  imports = [
    ../../modules/desktop/wayland.nix
    ../../modules/installer
  ];

  easyNix = {
    enable = true;
    # No update services on a medium: there is nothing to update, and the timers would
    # fire during the install and slow it down.
    update.enable = false;
    update.upgrade = false;
    powerwash.enable = false;
    # The first virtio disk, which is where the test harness puts the target.
    autoInstall = "/dev/vda";
  };
}
