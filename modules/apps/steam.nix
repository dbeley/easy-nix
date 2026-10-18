{ pkgs, lib, ... }:
/*
  Gaming.

  Wrapped in a platform guard rather than in a comment: Steam is x86-only, and the
  aarch64 flavour imports this same module set. On aarch64 the module becomes a no-op
  instead of a build failure.
*/
lib.mkIf pkgs.stdenv.hostPlatform.isx86_64 {
  hardware.graphics = {
    enable = true;
    # A number of Proton titles link 32-bit libraries.
    enable32Bit = lib.mkDefault true;
  };

  programs.steam = {
    enable = true;
    # Neither of these opens the firewall: an appliance should not listen on the
    # network because a game client asked it to.
    remotePlay.openFirewall = false;
    dedicatedServer.openFirewall = false;
    gamescopeSession.enable = true;
    extraCompatPackages = with pkgs; [ proton-ge-bin ];
  };

  programs.gamemode.enable = true;

  # ntsync is the kernel-side replacement for the winesync/fsync patches: lower
  # latency without patching the kernel, which matters on the low-end hardware this
  # project targets.
  boot.kernelModules = [ "ntsync" ];

  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "kernel.split_lock_mitigate" = 0;
  };

  environment.systemPackages = with pkgs; [
    mangohud
    protonup-qt
  ];
}
