# easy-nix maintenance. `just` with no arguments lists everything.
set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-load := false

host := "easy-nix"

# Format and lint (nixfmt, statix, deadnix, shfmt, shellcheck)
fmt:
    nix fmt

# The formatting gate (the same wrapper `nix fmt` uses) plus the static checks: cheap,
# and no host evaluation
check:
    nix build .#checks.x86_64-linux.formatting -L
    nix build .#checks.x86_64-linux.pre-commit-check -L

# Evaluate every host, one at a time, to stay within a small machine's memory.
# Uses the per-host target from the flake: for a host that exists to produce an image,
# that is its image variant rather than a top-level nobody boots.
eval:
    #!/usr/bin/env bash
    for h in easy-nix easy-nix-live easy-nix-live-test easy-nix-live-install-test easy-nix-arm; do
      printf '%-26s ' "$h"
      nix eval --raw ".#evalTargets.$h"
    done

# The installer ISO
iso:
    nix build .#packages.x86_64-linux.iso -L

# The light image the boot tests use
iso-test:
    nix build .#packages.x86_64-linux.iso-test -L

# Boot the light image under QEMU, BIOS then EFI. Needs /dev/kvm.
boot-test:
    nix build --option extra-sandbox-paths /dev/kvm -L .#checks.x86_64-linux.boot-test-bios
    nix build --option extra-sandbox-paths /dev/kvm -L .#checks.x86_64-linux.boot-test-efi

# Partition a virtual disk, install, then boot what was installed. Needs /dev/kvm, and
# about 10 GB of free space for the disk it writes.
install-test:
    nix build --option extra-sandbox-paths /dev/kvm -L .#checks.x86_64-linux.install-test

# Boot the image that ships, applications included. Slow.
boot-test-release:
    nix build --option extra-sandbox-paths /dev/kvm -L .#checks.x86_64-linux.boot-test-release-bios
    nix build --option extra-sandbox-paths /dev/kvm -L .#checks.x86_64-linux.boot-test-release-efi

# Boot the configured system in a VM, without an ISO
vm:
    nix build .#packages.x86_64-linux.vm -L

# The ARM SD-card image (experimental)
sd-card:
    nix build .#packages.aarch64-linux.sd-card -L

# Build this machine's system and make it the next boot target
boot host=host:
    sudo nixos-rebuild boot --flake ".#{{host}}" --no-write-lock-file

# Build and activate now
switch host=host:
    sudo nixos-rebuild switch --flake ".#{{host}}" --no-write-lock-file

# Bump the inputs. Only ever run to open a pull request, never on an appliance.
update:
    nix flake update
