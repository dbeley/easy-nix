/*
  Documents, at the size an appliance can justify: a PDF viewer and the tools to read one
  in a terminal. A full office suite is a closure nobody on a rescued machine opens twice
  a week; it belongs in Flathub (see `modules/flatpak.nix`), installed per machine by
  whoever wants it.
*/
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # French spelling and hyphenation, usable out of the box.
    hunspellDicts.fr-moderne
    hyphenDicts.fr-fr
    poppler-utils # pdftotext/pdfinfo: what "open a PDF" means in a terminal
    zathura
  ];
}
