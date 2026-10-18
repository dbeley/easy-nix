/*
  Installer layer.

  `live.nix` is what makes a configuration bootable and assertable, and is shared by
  the release medium and the light test image. `install.nix` adds the install tool and
  is only on the release medium, which keeps the test image small enough to boot
  anywhere.
*/
{
  imports = [
    ./live.nix
    ./install.nix
  ];
}
