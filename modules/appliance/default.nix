/*
  The appliance layer: what makes this an appliance rather than a machine somebody
  configured once - self-update, the options hosts switch it with, and powerwash.
*/
{
  imports = [
    ./options.nix
    ./auto-update.nix
    ./powerwash.nix
  ];
}
