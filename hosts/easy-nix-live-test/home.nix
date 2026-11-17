{ ... }:
{
  imports = [ ../../modules/desktop/labwc.nix ];

  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}
