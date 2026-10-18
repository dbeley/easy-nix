# Testing a real installation in a virtual machine

The boot test proves the medium reaches userspace. It proves **nothing** about the
installer: `easy-nix-install` has never partitioned a disk in that test, and no installed
system has ever been started. This procedure closes that gap by hand, on a machine with
KVM, until an automated version exists (see "Known gap" below).

Run it on any NixOS machine with `/dev/kvm` and about 60 GB free.

## 1. Fetch the published image, and check it

```sh
mkdir -p ~/easy-nix-test && cd ~/easy-nix-test
gh release download v0.1.0 --repo dbeley/easy-nix
cat easy-nix-*.iso.part-* > "$(awk '{print $2}' SHA256SUMS)"
sha256sum -c SHA256SUMS
gh attestation verify easy-nix-*.iso --repo dbeley/easy-nix
```

`gh attestation verify` prints nothing when its output is not a terminal; judge it on its
exit code, and note that it returns 0 only if the provenance names the file you hold.

## 2. Give the installer a disk to destroy

```sh
qemu-img create -f raw disk.img 32G
```

32 GB is the target hardware this project aims at. The file is sparse: it occupies what
the install actually writes, not 32 GB.

## 3. Boot the medium

```sh
nix shell nixpkgs#qemu -c qemu-system-x86_64 \
  -M q35 -m 4096 -smp 4 -enable-kvm -cpu host \
  -drive if=pflash,format=raw,readonly=on,file="$(nix eval --raw nixpkgs#OVMF.firmware)" \
  -drive file=disk.img,if=virtio,format=raw \
  -cdrom easy-nix-*.iso \
  -display gtk
```

- **UEFI, not BIOS.** The installer refuses to run on a machine that started in legacy
  BIOS mode, so the OVMF firmware line is required. `nix eval --raw nixpkgs#OVMF.firmware`
  is the `OVMF_CODE.fd` file itself, not the directory containing it.
- **`-display gtk` needs a screen.** On a headless machine use `-display none -vnc :1`
  and connect a VNC client. There is **no shell on the serial console**: the live image
  writes its kernel log and its `EASY_NIX_READY` marker to `/dev/ttyS0`, but autologin is
  on tty1, in a Wayland session. Everything interactive happens on the graphical console.

## 4. Install

In the VM, either launch **Install easy-nix** from the desktop, or open a terminal:

```sh
sudo easy-nix-install --disk /dev/vda
```

- **`/dev/vda`, not `/dev/sda`.** The disk is attached with virtio, so it appears as
  `vd*`. Check with `lsblk` if in doubt: the installer refuses a device that is not what
  you meant far less often than it should.
- Without `--disk` it asks which disk and then for confirmation; keep the interactive
  path for a first test, since that is the path a real user takes.
- `--yes` exists for automated installs and skips the confirmation.
- Expect several minutes: the system is copied from the medium, not downloaded.

Then shut the machine down (`sudo poweroff`) and remove the medium from the command
line, which is what makes the next boot use the disk.

## 5. Boot what was installed - the step that proves the point

```sh
nix shell nixpkgs#qemu -c qemu-system-x86_64 \
  -M q35 -m 4096 -smp 4 -enable-kvm -cpu host \
  -drive if=pflash,format=raw,readonly=on,file="$(nix eval --raw nixpkgs#OVMF.firmware)" \
  -drive file=disk.img,if=virtio,format=raw \
  -display gtk
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

## Known gap

This is a manual procedure, so it only runs when someone remembers. An automated version
needs a way in without a screen, and the medium does not have one today: a serial getty
(or an image variant that runs the installer at boot and writes its own marker to
`/dev/ttyS0`, in the shape of `EASY_NIX_READY`) would make it testable in CI, on every
push. Until then, this document is the test.
