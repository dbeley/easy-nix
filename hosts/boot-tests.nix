/*
  Boot tests, and the one test that installs.

  An image that has never been started is a hypothesis, so this is written before the
  release workflow exists and runs on every push.

  Three pairs, because they answer different questions:

    - `boot-test-*` boots the light image. It has to run everywhere, including a 2-core
      VM, so it asserts the *live machinery*: kernel, initrd, userspace, then the Wayland
      session on top. Two markers, in that order: `EASY_NIX_READY` from userspace, then
      `EASY_NIX_SESSION` from inside the session itself.
    - `boot-test-release-*` boots the image that actually ships, applications included.
      It is the expensive one, run by the release workflow on a runner with the RAM and
      the disk for it. The EFI half carries the session assertion too: the desktop is the
      product, and the release workflow must not be the first place it is known to work.
    - `install-test` boots the image that installs itself, waits for the installer's
      marker, then boots the disk it just wrote and waits for the installed machine's
      own marker. It is the only test that partitions anything, and it runs where the
      closure is warm.

  The session marker is written by `nix/session-report.sh`, from a systemd user unit in
  the session, and only after `niri msg` gets an answer. A process that is running proves
  nothing about a compositor that is drawing nothing; a client that connects and is
  answered proves the compositor is there.

  Both firmware paths are tested for the media: BIOS and EFI are separate boot chains,
  and an image can boot under one and not the other. The install test runs on EFI only,
  because the installer refuses a machine that started in legacy BIOS mode.

  The sandbox does not expose /dev/kvm, so the KVM device has to be given to the build
  explicitly (`--option extra-sandbox-paths /dev/kvm`), otherwise QEMU silently falls
  back to software emulation and the job times out instead of failing.
*/
{
  inputs,
  iso,
  isoRelease,
  isoInstallTest,
}:
let
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;

  # `pkgs.OVMF.firmware` is the code file itself, not a directory holding one.
  # Appending a filename to it produces a path that does not exist, and QEMU then
  # reports a missing firmware rather than anything pointing at the real mistake.
  qemuEnv = {
    QEMU = "${pkgs.qemu_kvm}/bin/qemu-kvm";
    OVMF_FIRMWARE = "${pkgs.OVMF.firmware}";
  };

  qemuInputs = with pkgs; [
    qemu_kvm
    bash
    coreutils
    gnugrep
    findutils
  ];

  mkBootTest =
    {
      name,
      image,
      mode,
      secondMarker ? null,
      mem ? "2048",
    }:
    pkgs.runCommand "easy-nix-boot-test-${name}"
      (
        qemuEnv
        // {
          nativeBuildInputs = qemuInputs;
          MARKER = "EASY_NIX_READY";
          SECOND_MARKER = if secondMarker == null then "" else secondMarker;
          MEM = mem;
          TIMEOUT = "900";
          MODE = mode;
        }
      )
      ''
        mkdir -p $out
        export ISO="$(find ${image}/iso -name '*.iso' | head -1)"
        # The runner writes serial.log into the current directory, and the build
        # directory is read-only; copying it into $out is what makes a failed boot
        # debuggable after the fact.
        cd "$TMPDIR"
        ${pkgs.bash}/bin/bash ${../nix/qemu-run.sh}
        cp serial.log $out/serial.log
        echo "mode=${mode}" > $out/result
      '';

  # The install test needs qemu-img as well, and writes two logs and a disk image. The
  # disk is left behind on purpose: it is created in the build directory, which is not
  # kept, and copying 24 GB into $out to fail a check faster would be absurd.
  mkInstallTest =
    { name, image }:
    pkgs.runCommand "easy-nix-install-test-${name}"
      (
        qemuEnv
        // {
          nativeBuildInputs = qemuInputs;
          # A full install fetches the system's closure and writes it: minutes, not
          # seconds, and the deadlines are per boot.
          TIMEOUT_INSTALL = "2700";
          TIMEOUT_BOOT = "900";
          DISK_SIZE = "24G";
        }
      )
      ''
        mkdir -p $out
        export ISO="$(find ${image}/iso -name '*.iso' | head -1)"
        cd "$TMPDIR"
        # The logs are copied on failure too: a check that fails without the serial
        # output attached cannot be debugged, and getting back to the failure costs a
        # full install.
        if ! ${pkgs.bash}/bin/bash ${../nix/install-test.sh}; then
          cp install.log boot.log $out/ 2>/dev/null || true
          exit 1
        fi
        cp install.log boot.log $out/
        echo "install=${name}" > $out/result
      '';
in
{
  boot-test-bios = mkBootTest {
    name = "bios";
    image = iso;
    mode = "bios";
  };
  boot-test-efi = mkBootTest {
    name = "efi";
    image = iso;
    mode = "efi";
    # The light image exists to prove the *live machinery*, and the session is part of
    # that: `EASY_NIX_READY` comes from a systemd oneshot in modules/base.nix, so it is
    # written whether niri draws a pixel or not. This second marker comes from inside the
    # session (nix/session-report.sh) and is what makes the claim in the header of this
    # file true rather than hopeful.
    #
    # 4 GiB, not the 2 GiB the userspace-only checks use: a compositor rendering through
    # llvmpipe needs the room, and an OOM kill would look like a broken session.
    secondMarker = "EASY_NIX_SESSION";
    mem = "4096";
  };
  boot-test-release-bios = mkBootTest {
    name = "release-bios";
    image = isoRelease;
    mode = "bios";
  };
  boot-test-release-efi = mkBootTest {
    name = "release-efi";
    image = isoRelease;
    mode = "efi";
    # Same assertion against the image that ships, applications and all: the release
    # workflow is not the first place a broken desktop is allowed to surface.
    secondMarker = "EASY_NIX_SESSION";
    mem = "4096";
  };
  install-test = mkInstallTest {
    name = "efi";
    image = isoInstallTest;
  };
}
