/*
  Documents, at the size an appliance can justify.

  LibreOffice was here and measured 2.7 GiB of closure for a suite nobody on a rescued
  machine opens twice a week: it was the second largest thing in the image, after Steam.
  What stays is what "open a document" actually means on such a machine - a PDF viewer
  and the tools to read one in a terminal - and Flathub for the rest (see
  `modules/flatpak.nix`), where a suite that is wanted can be installed per machine
  instead of shipped to every one.
*/
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # French spelling and hyphenation, so the suite is usable out of the box.
    hunspellDicts.fr-moderne
    hyphenDicts.fr-fr
    poppler-utils # pdftotext/pdfinfo: what "open a PDF" means in a terminal
    zathura
  ];
}
