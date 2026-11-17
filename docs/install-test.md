# Testing a real installation in a virtual machine

The boot test proves the medium reaches userspace. It proves **nothing** about the
installer: that is `checks.x86_64-linux.install-test`, which partitions a disk, installs
unattended and boots what it wrote (see "The automated version" below). This document is
for the parts the automated test does not cover - the released medium handled by hand, a
real physical disk, and the applications once the machine is up.

Run it on any NixOS machine with `/dev/kvm` and about 60 GB free.

## 1. Fetch the published image, and check it

```sh
mkdir -p ~/easy-nix-test && cd ~/easy-nix-test
gh release download --repo dbeley/easy-nix

iso=$(awk '$2 ~ /\.iso$/ {print $2}' SHA256SUMS)
cat easy-nix-*.iso.part-* > "$iso"
sha256sum -c SHA256SUMS
gh attestation verify "$iso" --repo dbeley/easy-nix
```

`SHA256SUMS` has one line per published file, hence the filter on the extension: taking
the second column of every line yields several names. `gh attestation verify` prints
nothing when its output is not a terminal; judge it on its exit code, and note that it
returns 0 only if the provenance names the file you hold.

## 2. Give the installer a disk to destroy

```sh
qemu-img create -f raw disk.img 32G
```

32 GB is the target hardware this project aims at. The file is sparse: it occupies what
the install actually writes, not 32 GB.

## 3. Boot the medium

Realise the firmware first, once per machine: `nix eval` prints a store path without
building it, so a machine that has never built that output gets `Could not open
'…OVMF_CODE.fd': No such file or directory`, which blames the firmware rather than the
missing build. Note the `fd`: it is one of OVMF's named outputs, not its default one.

```sh
nix build --no-link nixpkgs#OVMF.fd
nix shell nixpkgs#qemu -c qemu-system-x86_64 \
  -M q35 -m 4096 -smp 4 -enable-kvm -cpu host \
  -drive if=pflash,format=raw,readonly=on,file="$(nix eval --raw nixpkgs#OVMF.firmware)" \
  -drive file=disk.img,if=virtio,format=raw \
  -cdrom "$iso" \
  -device virtio-vga-gl -display gtk,gl=on
```

- **UEFI, not BIOS.** The installer refuses to run on a machine that started in legacy
  BIOS mode, so the OVMF firmware line is required. `nix eval --raw nixpkgs#OVMF.firmware`
  is the `OVMF_CODE.fd` file itself, not the directory containing it.
- **`-device virtio-vga-gl -display gtk,gl=on`, not a bare `-display gtk`.** QEMU's
  default VGA is a bochs card that mesa has no driver for, and a compositor is free to
  refuse software renderers. One that does starts, cannot allocate on the device, and runs
  headless, leaving the boot messages frozen on the screen with no error in them. virgl
  gives the guest a renderer the compositor accepts; host llvmpipe is enough.
- **The desktop is the only interface.** There is **no shell on the serial console**:
  the live image writes its kernel log and its `EASY_NIX_READY` marker to `/dev/ttyS0`,
  but autologin is on tty1, in a Wayland session. Everything interactive happens on the
  graphical console. On a machine with no screen at all, `-device virtio-vga-gl -display
  egl-headless -vnc :1` gives you that console over VNC.

## 4. Install

In the VM, either launch **Install easy-nix** from the desktop, or open a terminal:

```sh
sudo easy-nix-install --disk /dev/vda
```

- **`/dev/vda`, not `/dev/sda`.** The disk is attached with virtio, so it appears as
  `vd*`. Check with `lsblk` if in doubt.
- Without `--disk` it asks which disk and then for confirmation; keep the interactive
  path for a first test, since that is the path a real user takes.
- `--yes` exists for automated installs and skips the confirmation.
- Expect several minutes, plus the download: `nixos-install` works in the target's empty
  store, so the system is fetched from `cache.nixos.org` rather than copied out of the
  medium.

Then shut the machine down (`sudo poweroff`) and remove the medium from the command
line, which is what makes the next boot use the disk.

## 5. Boot what was installed - the step that proves the point

```sh
nix shell nixpkgs#qemu -c qemu-system-x86_64 \
  -M q35 -m 4096 -smp 4 -enable-kvm -cpu host \
  -drive if=pflash,format=raw,readonly=on,file="$(nix eval --raw nixpkgs#OVMF.firmware)" \
  -drive file=disk.img,if=virtio,format=raw \
  -device virtio-vga-gl -display gtk,gl=on
```

No `-cdrom`: it boots from the disk the installer wrote. The desktop should come up
without a password prompt. Inside the installed system, check the promises the README
makes rather than the ones you remember:

```sh
nixos-version
systemctl --failed                     # empty, or explain whatever is listed
ls -la /etc/easy-nix                   # a git checkout, not a copy
git -C /etc/easy-nix log --oneline -1
test -f /etc/easy-nix-local.nix || echo "absent until you create it (expected)"
sudo nixos-rebuild boot --flake /etc/easy-nix#easy-nix
```

That last one is the update path the timers run: if it fails, the appliance cannot
update itself, which is the whole point of the project.

## The automated version

```sh
nix build --option extra-sandbox-paths /dev/kvm .#checks.x86_64-linux.install-test
```

It boots the medium this repository releases, plus an unattended install: the test
configuration imports the released one and adds `easyNix.autoInstall`, which is set there
and nowhere else. What gets installed is therefore what a user installs, from the same
closure, and a change to the released medium is covered by this test without anyone keeping
two configurations in step.

It waits for the installer to report `EASY_NIX_INSTALLED` on the serial console, then boots
the disk it has just written and waits for the installed machine to report `EASY_NIX_READY`
- the marker every easy-nix machine writes when it reaches userspace, which is what makes
the second assertion possible without a screen.

What it does not cover, and what this document is still for: a real physical disk rather
than a sparse file, the released medium driven by hand, and anything about the applications
once the machine is up - the test asserts that a machine boots and installs, not that a
browser opens.
