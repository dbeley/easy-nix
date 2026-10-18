# easy-nix

A minimal, self-updating NixOS desktop. Wayland only, x86_64, installed from an ISO
that is built and boot-tested by CI.

Set up once, then forget about it: the machine fetches its own configuration, builds
the next generation in the background, and applies it at the next reboot. Personal
changes live in a file the updates never touch.

Not a Nix CLI wrapper. Despite the name, this is an operating system.

## What it is

| | |
|---|---|
| Base | NixOS unstable, flake-pinned (`flake.lock` committed) |
| Session | Wayland only: niri, foot, fuzzel, mako. `services.xserver.enable` is asserted false |
| Browsers | Firefox (policy-configured) and ungoogled-chromium |
| Office | LibreOffice + French spelling and hyphenation |
| Gaming | Steam, gamescope, gamemode, proton-ge, ntsync |
| Coding | OpenCode V2 (from the `llm-agents` catalogue flake) |
| Extra apps | Flathub, with GNOME Software as the store |
| Updates | Daily configuration fetch, weekly build, applied on reboot, five generations in the boot menu |
| Reset | `easy-nix-powerwash`: back to factory state without a medium |

Target hardware is the machine you would otherwise throw away: 4 GB of RAM, 32 GB of
disk, no discrete GPU. ZRAM instead of swap, `linuxPackages_latest`, and no server
daemon or container runtime anywhere in the image.

## Install

1. Download the ISO from the [releases page](../../releases).
2. Write it to a USB stick, then boot it. Verify the download first:

   ```sh
   sha256sum -c SHA256SUMS
   gh attestation verify easy-nix-*.iso --repo dbeley/easy-nix
   ```

3. Boot the stick. It comes up as a live system, so you can check the screen, the
   keyboard and the wifi before anything is written to a disk.
4. Either launch **Install easy-nix** from the desktop, or run it yourself:

   ```sh
   sudo easy-nix-install                 # asks which disk, then confirms
   sudo easy-nix-install --disk /dev/sda # for the impatient
   ```

   This erases the target disk. There is no encryption and no dual boot.

## Customising it, and why your changes survive

Everything under `/etc/easy-nix` is a git checkout that the machine fast-forwards.
Editing it does not do what you want: the update service refuses to run while it has
local modifications, rather than overwriting your work. That refusal is deliberate —
a distribution whose update silently deletes your changes is one nobody dares to edit.

Machine-specific changes go in **`/etc/easy-nix-local.nix`**, which is imported at
highest priority and is never written, reset or cleaned by anything in this repository:

```nix
# /etc/easy-nix-local.nix
{ ... }:
{
  # Keep the password prompt on sudo; the default is passwordless for a single-user
  # appliance.
  security.sudo.wheelNeedsPassword = true;

  # Anything else the module system accepts.
  environment.systemPackages = [ pkgs.mpv ];
}
```

Then `sudo nixos-rebuild boot --flake /etc/easy-nix#easy-nix` and reboot. The only
thing that removes this file is `easy-nix-powerwash`, and it says so before doing it.

## Updates

Two systemd timers, both of which can be turned off per host through the `easyNix`
options:

- **daily**, `easy-nix-update-config`: `git fetch` + fast-forward the configuration,
  then update Flatpaks.
- **weekly**, `easy-nix-upgrade`: fetch (as an `ExecStartPre`, so the two can never
  race and the rebuild always builds what the remote has now), then `nixos-rebuild boot
  --flake /etc/easy-nix#easy-nix --no-write-lock-file`, then notify any logged-in user
  that a reboot will apply it.

Three design decisions in there that matter more than the timers:

1. **Fast-forward or nothing.** Local modifications or a diverged branch stop the
   update and notify, instead of being resolved by force.
2. **`--no-write-lock-file`.** `flake.lock` is bumped by the `update-flake-lock`
   workflow and by nobody else, so every appliance runs the same pinned nixpkgs. Two
   machines built from the same ISO stay identical until someone decides otherwise.
3. **`boot`, not `switch`.** The running session is not replaced under the operator's
   hands, and a bad generation is one reboot away from being rolled back in the boot
   menu (`configurationLimit = 5`).

## Reset

```sh
sudo easy-nix-powerwash          # asks you to type POWERWASH
```

Removes `/etc/easy-nix-local.nix`, resets the checkout, empties the user's home,
restores `/etc/skel`, and makes the pristine system the next boot target. It does not
reformat the disk: handing the machine to someone else with a clean filesystem means
booting the installer again.

## ARM

Supported, as a **different product**, and marked experimental:

- There is no aarch64 installer ISO, because NixOS has none for ARM hardware. The
  deliverable is a flashable SD/eMMC image, built per board (`sd-card` image variant,
  `nixos-hardware` profiles). Raspberry Pi 4/5 is the assumed target.

  ```sh
  nix build .#packages.aarch64-linux.sd-card
  ```

- **No Steam.** Steam for Linux is x86-only, so the gaming half does not exist there.
- No Flathub, on purpose: fewer moving parts on a board nobody will debug.
- The CI evaluates the ARM configuration but cannot boot-test it; a boot test needs an
  arm64 runner or software emulation slow enough to time out.

## What it does not do

Stated here rather than discovered later:

- **No disk encryption, no dual boot.** Installing erases the target disk.
- **UEFI only.** Booting goes through systemd-boot, so a machine that starts in legacy
  BIOS mode is refused by the installer instead of being left unbootable. Supporting it
  means a `bios_grub` partition and GRUB bound to a device node, which is a change to
  both `modules/disk-layout.nix` and the partitioning step of the installer.
- **Autologin and passwordless sudo** are the default, because that is what makes an
  appliance behave like one. Anyone at the keyboard is root. One line in the local
  override file changes it.
- **No Widevine.** ungoogled-chromium cannot play DRM streaming services. Firefox can,
  if you install the plugin.
- **No touchscreen or tablet configuration** beyond what libinput autodetects.
- The boot test asserts the image reaches userspace; it does not assert that every
  application in it launches.

## Building

```sh
nix build .#packages.x86_64-linux.iso       # the installer ISO
nix build .#packages.x86_64-linux.iso-test  # the light image the boot tests use
nix build .#packages.x86_64-linux.vm        # boot the system in a VM
nix build .#packages.aarch64-linux.sd-card  # the SD-card image

nix eval --raw .#evalTargets.<host>          # evaluate one host, the honest way
just boot-test                               # boot the light image, BIOS + EFI
just fmt                                     # treefmt: nixfmt, statix, deadnix, shfmt
```

An ISO cannot be built on a small machine: expect 4 GB of closure and a lot of RAM.
The `iso` job in CI exists for that reason.

Do not run `nix flake check` on a machine with little memory: it evaluates all four
host configurations at once. `just eval` does them one at a time, `just check` builds
only the formatting checks.

`evalTargets` exists because "does this host evaluate" has four different answers. A
host that only exists to produce a medium — the two live images and the ARM one — is
evaluated through its image variant, which is where its filesystem layout comes from.
Evaluating `system.build.toplevel` on those fails an assertion about a missing root
filesystem, correctly: there is no such system.

## Layout

```
flake.nix                  inputs, per-system outputs, checks
hosts/
  default.nix              mkHost: wires base + home-manager + specialArgs
  easy-nix/                the installed appliance
  easy-nix-live/           the released installer ISO
  easy-nix-live-test/      a light image, only so boot tests run anywhere
  easy-nix-arm/            the SD-card image (experimental)
  boot-tests.nix           the QEMU checks
modules/
  base.nix                 locale, networking, audio, nix, the user
  disk-layout.nix          by-label partitions, systemd-boot
  appliance/               options, self-update, notifications, powerwash
  desktop/                 Wayland session and niri configuration
  apps/                    browsers, office, steam, opencode
  installer/               live medium settings and easy-nix-install
scripts/nix/qemu-run.sh    the boot harness
```

## Credits

The idea of a self-updating, reset-able NixOS desktop, and the shape of the update
timers, come from [nixbook](https://github.com/mkellyxp/nixbook) by Mike Kelly (MIT).
easy-nix is a separate project rather than a fork: it targets Wayland and experienced
users, and it replaces the piece of nixbook's design that makes customisation unsafe —
an update that resets the configuration checkout to its remote.

MIT licensed. See `LICENSE`.
