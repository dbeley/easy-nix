/*
  The medium the install test boots: the released one, plus an unattended install onto
  the disk the test attaches.

  It imports the released medium rather than approximating it, so the test installs what
  a user installs, from the same closure and with no network involved - and any change to
  the released medium is covered here without a second configuration to keep in step.

  `autoInstall` is set here and nowhere else: nothing that ships installs itself.
*/
{
  ...
}:
{
  imports = [ ../easy-nix-live ];

  easyNix.autoInstall = "/dev/vda";
}
