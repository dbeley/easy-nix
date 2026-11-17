# easy-nix maintenance. `just` with no arguments lists everything.
set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-load := false

host := "easy-nix"

# Every recipe name is `<verb>-<noun>`, and both vocabularies are closed:
#
#   build-  produce a file under result/, boot nothing
#   run-    boot it in QEMU and let you look at it
#   test-   boot it in QEMU and fail if it did not report itself
#
#   light    the CI-only medium: no applications, no installer (~2 GiB)
#   iso      the installer ISO that ships (~4 GiB)
#   install  the shipped image plus an unattended install onto /dev/vda
#   vm       the installed system, booted without any medium
#
#            light          iso         install      vm
#   build    build-light    build-iso   -            -
#   run      run-light      run-iso     run-install  run-vm
#   test     test-light     test-iso    test-install -
#
# The `install` medium and the `vm` are not products: `run-install` and `test-install`
# build them on demand, because nobody wants the file, they want the machine.
#
# `just boot` is `nixos-rebuild boot` on *this* machine, which is why the QEMU verb is
# `run`. The same rule covers the ARM image (`build-sd-card`) and the size budgets
# (`test-size`). The old names still work as aliases; see the bottom of this file.

# Format the tree in place (nixfmt, statix, deadnix, shfmt, shellcheck)
fmt:
    nix fmt

# Run the formatting gate and the static hooks; no host is evaluated (< 1 min)
check:
    nix build .#checks.x86_64-linux.formatting -L
    nix build .#checks.x86_64-linux.pre-commit-check -L

# Evaluate every host, one at a time; prints each drv path (~1 min, no builds)
eval:
    #!/usr/bin/env bash
    for h in easy-nix easy-nix-live easy-nix-live-test easy-nix-live-install-test easy-nix-arm; do
      printf '%-26s ' "$h"
      nix eval --raw ".#evalTargets.$h"
    done

# Build the installer ISO that ships into result/iso (~4 GiB, ~40 min, needs ~25 GB free)
build-iso:
    nix build .#packages.x86_64-linux.iso -L
    ls -lh result/iso/*.iso

# Build the light medium the tests use into result/iso (~2 GiB, minutes)
build-light:
    nix build .#packages.x86_64-linux.iso-test -L
    ls -lh result/iso/*.iso

# Boot the light medium with the serial console on this terminal (no display needed)
run-light:
    #!/usr/bin/env bash
    # The medium, booted for real, on this machine: Ctrl-A X quits, Ctrl-A C is the QEMU
    # monitor. The light medium carries the session but no applications and no installer;
    # `just run-iso` boots the image that ships and `just run-install` gives it a disk.
    #
    # KVM is not optional - without it QEMU falls back to software emulation and the
    # session takes tens of minutes to appear - and 4 GiB is the floor for a compositor
    # rendering through llvmpipe.
    set -eo pipefail
    iso=$(nix build --print-out-paths .#packages.x86_64-linux.iso-test 2>/dev/null | tail -1)
    qemu=$(nix build --no-link --print-out-paths nixpkgs#qemu_kvm 2>/dev/null | tail -1)
    ovmf=$(nix build --no-link --print-out-paths 'nixpkgs#OVMF.fd' 2>/dev/null | tail -1)
    exec "$qemu/bin/qemu-kvm" -machine q35 -m 4096 -smp 4 -no-reboot -nographic \
      -cdrom "$(echo "$iso"/iso/*.iso)" \
      -drive "if=pflash,format=raw,readonly=on,file=$ovmf/FV/OVMF_CODE.fd" \
      -enable-kvm -cpu host

# Boot the installer ISO in a window, applications included (needs a display and GL)
run-iso:
    #!/usr/bin/env bash
    # `-device virtio-vga-gl` with `gl=on`, never QEMU's default VGA.
    #
    # The default `-vga std` is a bochs card that mesa has no driver for, and niri -
    # the compositor before labwc - refused software renderers outright: it started,
    # could not allocate a buffer on the device, logged `no allocator available for
    # device` and ran *headless*, leaving the autologin line frozen on the console.
    # virgl gives the guest a virtio_gpu renderer the compositor accepts, and host
    # llvmpipe is enough: what the guest needs is a device it can allocate from, not
    # speed.
    set -eo pipefail
    iso=$(nix build --print-out-paths .#packages.x86_64-linux.iso 2>/dev/null | tail -1)
    qemu=$(nix build --no-link --print-out-paths nixpkgs#qemu_kvm 2>/dev/null | tail -1)
    ovmf=$(nix build --no-link --print-out-paths 'nixpkgs#OVMF.fd' 2>/dev/null | tail -1)
    exec "$qemu/bin/qemu-kvm" -machine q35 -m 4096 -smp 4 -no-reboot \
      -device virtio-vga-gl -display gtk,gl=on -serial mon:stdio \
      -cdrom "$(echo "$iso"/iso/*.iso)" \
      -drive "if=pflash,format=raw,readonly=on,file=$ovmf/FV/OVMF_CODE.fd" \
      -enable-kvm -cpu host

# Boot the self-installing medium with a blank 24 GiB disk; it installs, reports, powers off
run-install disk="/tmp/easy-nix-disk.img":
    #!/usr/bin/env bash
    # The whole install path without a USB stick: the medium partitions and installs onto
    # the attached virtio disk, then you can boot that disk by rebooting the same QEMU and
    # dropping -cdrom. `disk` is created if it is missing and NOT deleted afterwards.
    set -eo pipefail
    [ -f "{{disk}}" ] || qemu-img create -f raw "{{disk}}" 24G
    iso=$(nix build --print-out-paths .#packages.x86_64-linux.iso-install-test 2>/dev/null | tail -1)
    qemu=$(nix build --no-link --print-out-paths nixpkgs#qemu_kvm 2>/dev/null | tail -1)
    ovmf=$(nix build --no-link --print-out-paths 'nixpkgs#OVMF.fd' 2>/dev/null | tail -1)
    exec "$qemu/bin/qemu-kvm" -machine q35 -m 4096 -smp 4 -no-reboot -nographic \
      -cdrom "$(echo "$iso"/iso/*.iso)" \
      -drive "if=pflash,format=raw,readonly=on,file=$ovmf/FV/OVMF_CODE.fd" \
      -drive "file={{disk}},if=virtio,format=raw" \
      -enable-kvm -cpu host

# Boot the installed appliance in a VM, no installer and no medium (nixos-rebuild build-vm)
run-vm:
    nix build .#packages.x86_64-linux.vm -L
    ./result/bin/run-*-vm

# Boot the light medium and fail unless userspace and the session report (CI runs this)
test-light:
    #!/usr/bin/env bash
    # KVM is mandatory (no KVM means software emulation, which times out instead of
    # failing). The render node is not: when this machine has a GPU, handing it to the
    # sandbox makes the guest boot with virgl, and the session check then asserts an
    # output instead of accepting a compositor that draws nothing. Without a GPU the
    # check says so and stays honest about what it did not prove.
    set -eo pipefail
    paths=/dev/kvm
    [ -e /dev/dri/renderD128 ] && paths="$paths /dev/dri"
    nix build --option extra-sandbox-paths "$paths" -L .#checks.x86_64-linux.boot-test-bios
    nix build --option extra-sandbox-paths "$paths" -L .#checks.x86_64-linux.boot-test-efi

# Boot the installer ISO, applications included, and assert the session too (slow)
test-iso:
    #!/usr/bin/env bash
    # Same render-node rule as `test-light`: this is the image that ships, so the one
    # assertion worth having is that its desktop really draws.
    set -eo pipefail
    paths=/dev/kvm
    [ -e /dev/dri/renderD128 ] && paths="$paths /dev/dri"
    nix build --option extra-sandbox-paths "$paths" -L .#checks.x86_64-linux.boot-test-release-bios
    nix build --option extra-sandbox-paths "$paths" -L .#checks.x86_64-linux.boot-test-release-efi

# Partition a virtual disk, install, boot what was installed (needs ~10 GB free, slow)
test-install:
    nix build --option extra-sandbox-paths /dev/kvm -L .#checks.x86_64-linux.install-test

# Print the measured image sizes next to their budgets; fails if either grew past it
test-size:
    nix build --no-link -L .#packages.x86_64-linux.size-budget-test
    nix build --no-link -L .#packages.x86_64-linux.size-budget-installer

# Build the ARM SD-card image (experimental; aarch64, never boot-tested by CI)
build-sd-card:
    nix build .#packages.aarch64-linux.sd-card -L

# Build this machine's system and make it the next boot target; does not restart anything
boot host=host:
    sudo nixos-rebuild boot --flake ".#{{host}}" --no-write-lock-file

# Build and activate this machine's system now, in the running session
switch host=host:
    sudo nixos-rebuild switch --flake ".#{{host}}" --no-write-lock-file

# Move flake.lock to the current inputs. For opening a pull request, never for an appliance
update:
    nix flake update

# The names these recipes had before they were grouped by verb. Kept so that a command
# copied out of an older shell history or an older README still does the right thing.
alias iso := build-iso
alias iso-test := build-light
alias run := run-light
alias run-disk := run-install
alias vm := run-vm
alias boot-test := test-light
alias boot-test-release := test-iso
alias install-test := test-install
alias size := test-size
alias sd-card := build-sd-card
