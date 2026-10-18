# easy-nix maintenance. `just` with no arguments lists everything.
set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-load := false

host := "easy-nix"

# Format and lint (nixfmt, statix, deadnix, shfmt, shellcheck)
fmt:
    nix fmt

# The formatting/linting checks only: cheap, no host evaluation
check:
    nix build .#checks.x86_64-linux.pre-commit-check -L

# Evaluate every host, one at a time, to stay within a small machine's memory
eval:
    #!/usr/bin/env bash
    for h in easy-nix easy-nix-live easy-nix-live-test easy-nix-arm; do
      echo "==> $h"
      nix eval --no-write-lock-file ".#nixosConfigurations.$h.config.system.build.toplevel.drvPath"
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
