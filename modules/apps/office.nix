/*
  Office suite: LibreOffice from nixpkgs rather than from Flathub.

  A store package is reproducible, updates with the system, and does not need a
  second package manager to be healthy. Flathub stays available for the applications
  nixpkgs does not carry (see `modules/flatpak.nix`), which is the case Zoom and most
  vendor desktop apps fall into.
*/
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    libreoffice
    # French spelling and hyphenation, so the suite is usable out of the box.
    hunspellDicts.fr-moderne
    hyphenDicts.fr-fr
    poppler-utils # pdftotext/pdfinfo: what "open a PDF" means in a terminal
    zathura
  ];
}
