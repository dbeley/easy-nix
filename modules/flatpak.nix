/*
  Flathub, for the applications nixpkgs does not carry.

  Deliberately the only second source of packages. Adding a second one is how a
  "minimal" system stops being minimal, and every extra source is another thing that
  can be broken on a machine nobody administers.

  The Flathub remote is added by a oneshot service rather than by hand, so a
  powerwashed or freshly installed machine has it without an operator remembering to.
*/
{ pkgs, ... }:
{
  services.flatpak.enable = true;

  systemd.services.flatpak-flathub-remote = {
    description = "Add the Flathub remote";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists --system \
        flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    '';
  };

  systemd.services.flatpak-flathub-remote.wantedBy = [ "multi-user.target" ];

  # A store, so installing software does not require knowing about flatpak. It is
  # also the only GUI that can find the applications this system does not ship.
  environment.systemPackages = with pkgs; [
    flatpak
    gnome-software
  ];
}
