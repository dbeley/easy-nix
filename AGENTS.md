# Repository Guidelines

## What this is

A NixOS distribution: a flake that produces a bootable installer ISO, a self-updating
installed system, and (experimentally) an ARM SD-card image. It is not a Nix helper
library and it exposes no library API.

## Layout

- `flake.nix` - inputs and outputs. `flake-parts` + `treefmt-nix`; hosts are built in
  `hosts/default.nix` and exposed as `nixosConfigurations`, `packages`, `evalTargets`
  and `checks`.
- `hosts/default.nix` - `mkHost`, which wires `modules/base.nix`, home-manager and the
  `specialArgs` (`user`, `hostName`, `stateVersion`, `inputs`, `flakeSelf`).
- `hosts/<host>/default.nix` - a system configuration; `hosts/<host>/home.nix` - the
  home-manager side of the same host.
- `modules/base.nix` - what every host shares. Never a bootloader, never `fileSystems`,
  never the desktop.
- `modules/disk-layout.nix` - partitions referenced by **label**
  (`/dev/disk/by-partlabel/NIXROOT`), never by device node, so the installer can target
  `/dev/sda`, `/dev/nvme0n1` or `/dev/mmcblk0` and every later rebuild still resolves the
  same filesystems. Keep the partitioning step of `modules/installer/install.nix` in step
  with this file.
- `modules/appliance/` - the self-update and reset machinery, behind the `easyNix.*`
  options declared in `options.nix`.
- `modules/desktop/` - niri configuration (home-manager) and the system-side session.
- `modules/apps/` - one file per application group. Steam is inside a platform guard so
  the aarch64 flavour can import the same set.
- `modules/installer/` - `live.nix` makes a configuration bootable and assertable;
  `install.nix` adds `easy-nix-install` and is only on the release medium.
- `.github/workflows/` - `ci.yml` (lint, evaluate every host, boot-test, build the ISO),
  `release.yml` (tag → build → boot-test the real image → attest → publish),
  `update-flake-lock.yml`.

## Rules that are not negotiable

1. **Wayland only.** `services.xserver.enable` must stay false; an assertion enforces it.
   An application that needs X goes through `xwayland-satellite`.
2. **The update service never destroys work.** `git merge --ff-only`, never
   `reset --hard`, and stop with a notification on local modifications or divergence.
   `reset --hard` is correct in exactly one place: `easy-nix-powerwash`, where the
   operator has asked for destruction and is told so.
3. **`flake.lock` moves upstream only.** The update service runs
   `nixos-rebuild --no-write-lock-file`. A machine that rewrites its own lock file breaks
   the guarantee that two appliances built from the same ISO stay identical.
4. **User customisation lives outside the checkout**, in `easyNix.localOverrideFile`.
   Nothing in this repository may write, reset or clean that path except powerwash.
5. **`boot`, not `switch`,** in anything automated: never replace the running session
   under the operator's hands.

## Testing

Do not run `nix flake check` on a machine with little memory: it evaluates all four hosts
at once and wants 12 GB+. Use, in increasing cost:

```sh
nix fmt                 # treefmt: nixfmt, statix, deadnix, shfmt
nix build .#checks.x86_64-linux.formatting -L        # the same wrapper `nix fmt` uses
nix build .#checks.x86_64-linux.pre-commit-check -L  # shellcheck, EOF, whitespace
just eval               # one host at a time, through `evalTargets`
just boot-test          # boots the light image, BIOS and EFI; needs /dev/kvm
```

`evalTargets` exists because "does this host evaluate" has four different answers. A host
that only exists to produce a medium is evaluated through its image variant, which is
where its filesystem layout comes from; evaluating `system.build.toplevel` on those fails
an assertion about a missing root filesystem, correctly - there is no such system.

The boot test is the only thing that proves an image is an image. It needs the KVM device
handed to the sandbox, or QEMU silently falls back to software emulation and the job times
out instead of failing:

```sh
nix build --option extra-sandbox-paths /dev/kvm -L .#checks.x86_64-linux.boot-test-bios
```

The marker `EASY_NIX_READY` must appear in `result/serial.log`, together with the autologin
prompt.

## Pitfalls already paid for

- `boot.consoleLogLevel`, not `loglevel=` in `boot.kernelParams`: nixpkgs appends its own
  loglevel afterwards and the serial console goes mute, which makes a failed boot
  undiagnosable.
- `isoImage.*` and `sdImage.*` are declared by the image module, which only the variant
  imports: set them under `image.modules.<variant>`, never on the host configuration.
  `image.baseName` is assigned by `iso-image.nix` without `mkDefault`, so overriding it
  needs `lib.mkForce`.
- `pkgs.OVMF.firmware` is the `OVMF_CODE.fd` file itself, not a directory holding one.
  Appending a filename to it makes the EFI boot test fail on a missing firmware.
- `boot.kernelPackages` is set with `lib.mkOverride 1200` in `modules/base.nix` so that a
  board profile pinning its own kernel with `mkDefault` wins. A plain assignment would
  collide; `mkDefault` would collide too, both sitting at the same priority.
- niri has no concept of `Terminal=true`: a desktop entry that prompts must name its
  terminal (`foot -e …`) or it runs with no tty and does nothing visible.
- `environment.systemPackages` twice in the same module is a conflict, not a merge.
- Inside a Nix `''` string, a shell `''${VAR}` needs escaping and `$VAR` does not.
  Shellcheck passing does not prove the escaping worked - read the generated script
  (`nix-store --realise <the .drv>`, then `$out/bin/<name>`).
- In a git flake, `git add` before `nix eval` on a fresh checkout: untracked files are
  invisible to Nix, and the error points at a file you just wrote.
- The formatting check and the pre-commit hooks must not run the same formatter with
  different defaults (treefmt's `shfmt` uses two spaces, the hook's uses tabs): the check
  runs `config.treefmt.build.wrapper` with `--no-cache --fail-on-change`, and the hooks
  keep only shellcheck, end-of-file and trailing-whitespace.
- A desktop closure does not fit on a CI runner's default disk: the `iso` job frees the
  toolchains it does not use and then verifies the result, because a mid-build "No space
  left on device" looks like a network problem and is not one.
