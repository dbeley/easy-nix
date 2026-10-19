/*
  The medium the install test boots: the released one, plus an unattended install onto the
  disk the test attaches.

  It imports the released medium rather than approximating it, and that is the point. An
  earlier version was a second, lighter configuration that happened to include the
  installer, so what it installed was not what a user installs: the light medium carries
  neither the applications nor the system they make up, so `nixos-install` had to fetch and
  build a desktop closure inside the guest. That needs a resolver working seconds after
  boot and a writable store with room for the whole closure - a test of the network, not of
  the installer, and it failed in CI for exactly that reason, twice, with the disk already
  partitioned and mounted.

  By importing the released configuration, the test installs what users install, from the
  same closure, with no network involved; and any change to the released medium is covered
  by this test without anyone remembering to keep two configurations in step.

  `autoInstall` is set here and nowhere else: nothing that ships installs itself.
*/
{
  ...
}:
{
  imports = [ ../easy-nix-live ];

  easyNix.autoInstall = "/dev/vda";
}
