/*
  Boot tests.

  An image that has never been started is a hypothesis, so this is written before the
  release workflow exists and runs on every push.

  Two pairs, because they answer different questions:

    - `boot-test-*` boots the light image. It has to run everywhere, including a 2-core
      VM, so it asserts the *live machinery*: kernel, initrd, userspace, Wayland session.
    - `boot-test-release-*` boots the image that actually ships, applications included.
      It is the expensive one, run by the release workflow on a runner with the RAM and
      the disk for it.

  Both firmware paths are tested: BIOS and EFI are separate boot chains, and an image
  can boot under one and not the other.

  The sandbox does not expose /dev/kvm, so the KVM device has to be given to the build
  explicitly (`--option extra-sandbox-paths /dev/kvm`), otherwise QEMU silently falls
  back to software emulation and the job times out instead of failing.
*/
{
  inputs,
  iso,
  isoRelease,
}:
let
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;

  mkBootTest =
    {
      name,
      image,
      mode,
    }:
    pkgs.runCommand "easy-nix-boot-test-${name}"
      {
        nativeBuildInputs = with pkgs; [
          qemu_kvm
          bash
          coreutils
          gnugrep
          findutils
        ];
        MARKER = "EASY_NIX_READY";
        TIMEOUT = "900";
        MODE = mode;
        QEMU = "${pkgs.qemu_kvm}/bin/qemu-kvm";
        # `pkgs.OVMF.firmware` is the code file itself, not a directory holding one.
        # Appending a filename to it produces a path that does not exist, and QEMU then
        # reports a missing firmware rather than anything pointing at the real mistake.
        OVMF_FIRMWARE = "${pkgs.OVMF.firmware}";
      }
      ''
        mkdir -p $out
        export ISO="$(find ${image}/iso -name '*.iso' | head -1)"
        # The runner writes serial.log into the current directory, and the build
        # directory is read-only; copying it into $out is what makes a failed boot
        # debuggable after the fact.
        cd "$TMPDIR"
        ${pkgs.bash}/bin/bash ${../scripts/nix/qemu-run.sh}
        cp serial.log $out/serial.log
        echo "mode=${mode}" > $out/result
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
}
