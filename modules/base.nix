/*
  System base shared by every easy-nix host: locale, time, networking, audio, nix
  settings, the single user account.

  Deliberately absent, because they belong to a host and not to the base:
    - any bootloader (the disk image and the ISO each bring their own)
    - `fileSystems` (declared by `modules/disk-layout.nix`)
    - the desktop (see `modules/desktop/`)
*/
{
  config,
  lib,
  pkgs,
  user,
  hostName,
  stateVersion,
  ...
}:
{
  system.stateVersion = stateVersion;
  networking.hostName = lib.mkDefault hostName;

  # The newest stable kernel.
  #
  # `mkOverride 1200` rather than a plain value or `mkDefault`, and the number is the
  # whole point: a board profile that pins its own kernel does so with `mkDefault`
  # (priority 1000), which wins over this. So x86 gets the latest kernel, and the
  # Raspberry Pi keeps the downstream kernel it actually needs. With a plain assignment
  # the two would collide; with `mkDefault` they would collide too, since both would sit
  # at the same priority.
  boot.kernelPackages = lib.mkOverride 1200 pkgs.linuxPackages_latest;

  # --- networking -----------------------------------------------------------
  networking.networkmanager = {
    enable = true;
    # iwd rather than wpa_supplicant: magnitudes faster on resume for wifi laptops.
    wifi.backend = "iwd";
  };
  networking.firewall.enable = lib.mkDefault true;

  services.resolved.enable = true;

  # --- locale and time ------------------------------------------------------
  time.timeZone = lib.mkDefault "Europe/Paris";
  i18n.defaultLocale = lib.mkDefault "fr_FR.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "fr_FR.UTF-8";
    LC_IDENTIFICATION = "fr_FR.UTF-8";
    LC_MEASUREMENT = "fr_FR.UTF-8";
    LC_MONETARY = "fr_FR.UTF-8";
    LC_NAME = "fr_FR.UTF-8";
    LC_NUMERIC = "fr_FR.UTF-8";
    LC_PAPER = "fr_FR.UTF-8";
    LC_TELEPHONE = "fr_FR.UTF-8";
    LC_TIME = "fr_FR.UTF-8";
  };

  # --- storage hygiene ------------------------------------------------------
  # Compression in RAM instead of a swap partition: the target is a 4 GB, disk-only
  # machine, where a swap file is both slow and a threat to the disk's lifespan.
  zramSwap.enable = true;
  zramSwap.memoryPercent = lib.mkDefault 50;

  boot.tmp.useTmpfs = true;

  services.fstrim.enable = true;
  services.journald.settings.Journal = {
    SystemMaxUse = "100M";
    SystemMaxFileSize = "10M";
  };

  # --- audio / bluetooth / printing ----------------------------------------
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };
  security.rtkit.enable = true;

  hardware.bluetooth.enable = true;
  hardware.enableAllHardware = lib.mkDefault true;

  # Printing is opt-in: it drags avahi and cups into a machine that usually does not
  # print, and it is one line to turn on.
  services.printing.enable = lib.mkDefault false;

  # --- nix ------------------------------------------------------------------
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
    trusted-users = [
      "root"
      user
    ];
    # Keep the last two generations substitutable without rebuilding them.
    keep-outputs = true;
    keep-derivations = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  nixpkgs.config = {
    allowUnfree = true;
  };

  # --- user -----------------------------------------------------------------
  users.mutableUsers = true;
  users.users.${user} = {
    isNormalUser = true;
    description = "easy-nix";
    extraGroups = [
      "networkmanager"
      "wheel"
      "video"
      "audio"
    ];
    shell = pkgs.bash;
    # Only applied while the account has no password of its own. `users.mutableUsers` is
    # true, so `passwd` replaces it and no rebuild puts it back.
    initialPassword = lib.mkIf (
      config.easyNix.user.initialPassword != null
    ) config.easyNix.user.initialPassword;
  };

  security.sudo.wheelNeedsPassword = false;

  # --- shell invocation -----------------------------------------------------
  environment.systemPackages = with pkgs; [
    git
    curl
    htop
    pciutils
    usbutils
    wget
  ];

  # --- the appliance layer --------------------------------------------------
  imports = [
    ../modules/appliance
  ];
}
