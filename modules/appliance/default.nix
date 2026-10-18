/*
  The appliance layer: everything that makes this an appliance rather than a
  machine somebody configured once.

  Order matters only in that options must exist before the services that read them.
*/
{
  imports = [
    ./options.nix
    ./auto-update.nix
    ./powerwash.nix
  ];
}
