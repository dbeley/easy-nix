/*
  Flathub, for the applications nixpkgs does not carry, and deliberately the only second
  source of packages: every extra source is another thing that can break on a machine
  nobody administers.

  The remote is added by a oneshot service rather than by hand, so a freshly installed or
  powerwashed machine has it without an operator remembering to.
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

  # A store, so installing software does not require knowing about flatpak, and the only
  # GUI that can find what this system does not ship.
  environment.systemPackages = with pkgs; [
    flatpak
    gnome-software
  ];
}
