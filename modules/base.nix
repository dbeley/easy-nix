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

  # The newest stable kernel, at priority 1200: a board profile that pins its own kernel
  # does so with `mkDefault` (1000) and must win, so x86 gets the latest kernel while the
  # Raspberry Pi keeps the downstream one it needs. A plain assignment or `mkDefault` here
  # would collide with it instead.
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
  # Compression in RAM instead of a swap partition: on a 4 GB disk-only machine a swap
  # file is both slow and a threat to the disk's lifespan.
  zramSwap.enable = true;
  zramSwap.memoryPercent = lib.mkDefault 50;

  boot.tmp.useTmpfs = true;

  # The option's default (`true` until 26.11) is for machines importing a pool named
  # `root` at boot, which on an appliance is the disaster it guards against - and it warns
  # about that at evaluation time. No ZFS here, so off.
  boot.zfs.forceImportRoot = false;

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
      # The session report writes its marker to /dev/ttyS0 (root:tty 0660); without this
      # the boot test's second assertion depends on journal forwarding instead.
      "tty"
    ];
    shell = pkgs.bash;
    # Only applied while the account has no password of its own. `users.mutableUsers` is
    # true, so `passwd` replaces it and no rebuild puts it back.
    initialPassword = lib.mkIf (
      config.easyNix.user.initialPassword != null
    ) config.easyNix.user.initialPassword;
  };

  security.sudo.wheelNeedsPassword = false;

  # --- the operator's only view of a headless machine -----------------------
  # The target is a machine with no display attached, so the serial console is the only
  # way to see a boot - and it is what the install test reads to watch an *installed*
  # system come up.
  #
  # `consoleLogLevel`, not `loglevel=` in `kernelParams`: nixpkgs appends its own
  # `loglevel=` afterwards, the kernel argument loses to it and the console stays mute.
  boot.kernelParams = [ "console=ttyS0,115200" ];
  boot.consoleLogLevel = 7;

  systemd.services.easy-nix-ready = {
    description = "Announce that the machine reached userspace";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Written to /dev/ttyS0 explicitly: /dev/console is not reliable for this, since
      # which device it points at depends on the order of the `console=` arguments.
      msg="EASY_NIX_READY label=${config.system.nixos.label}"
      echo "$msg" > /dev/ttyS0 || true
      echo "$msg" > /dev/console || true
    '';
  };

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
