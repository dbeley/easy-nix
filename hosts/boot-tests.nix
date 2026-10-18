/*
  Boot tests, and the one test that installs.

  An image that has never been started is a hypothesis, so this is written before the
  release workflow exists and runs on every push.

  Three pairs, because they answer different questions:

    - `boot-test-*` boots the light image. It has to run everywhere, including a 2-core
      VM, so it asserts the *live machinery*: kernel, initrd, userspace, Wayland session.
    - `boot-test-release-*` boots the image that actually ships, applications included.
      It is the expensive one, run by the release workflow on a runner with the RAM and
      the disk for it.
    - `install-test` boots the image that installs itself, waits for the installer's
      marker, then boots the disk it just wrote and waits for the installed machine's
      own marker. It is the only test that partitions anything, and it runs where the
      closure is warm.

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
    }:
    pkgs.runCommand "easy-nix-boot-test-${name}"
      (
        qemuEnv
        // {
          nativeBuildInputs = qemuInputs;
          MARKER = "EASY_NIX_READY";
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
        ${pkgs.bash}/bin/bash ${../nix/install-test.sh}
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
  };
  install-test = mkInstallTest {
    name = "efi";
    image = isoInstallTest;
  };
}
