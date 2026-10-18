# Security policy

## Reporting a vulnerability

Use GitHub's private vulnerability reporting:
**https://github.com/dbeley/easy-nix/security/advisories/new**

Please do not open a public issue for anything that lets someone who is not the machine's
owner do something to it. Reports are read by the maintainer alone.

## What this project is, and where the trust sits

easy-nix builds an operating system image and hands it to you. That shape decides what
"a vulnerability" means here, so the trust boundary is stated rather than implied.

**What is trusted**

- The repository, at the revision you clone or that your machine fast-forwards to. The
  self-update path is `git pull --ff-only` over HTTPS, and nothing else: there is no
  signature on the update channel beyond TLS and GitHub's own authentication. A compromise
  of this repository, or of the account that publishes it, is a compromise of every
  appliance that follows it. That is the largest single assumption in the design.
- The NixOS and nixpkgs revisions pinned in `flake.lock`, and the binary cache those
  revisions point at.
- The ISO built from this repository, once you have checked it against the published
  `SHA256SUMS` and the build provenance attestation. Until then it is an unverified file
  from the internet.

**What is deliberately not trusted**

- **Anything installed from Flathub.** It is a second, unverified source of software, and
  the only one this system enables. A Flatpak application runs with the permissions its
  own manifest asks for, which this project does not review.
- **The network.** Updates are fetched over the public internet; there is no offline
  signing infrastructure.
- **The medium.** The installer refuses the device it booted from, refuses a device with
  mounted filesystems, and refuses a machine that started in legacy BIOS mode. Everything
  else about the target disk is the operator's decision, including `--disk /dev/wrong`.

**Known trade-offs, not vulnerabilities**

These are documented choices. A report that someone with physical access to an appliance
can reach root is out of scope, because it is the intended behaviour:

- autologin on tty1, so the desktop appears without a password;
- passwordless `sudo` for the `wheel` group, so updates and a reset need no password;
- no disk encryption, and no dual boot: installing erases the target disk;
- a configuration checkout at `/etc/easy-nix` that the machine fast-forwards on its own.

`/etc/easy-nix-local.nix` is the supported place for machine-specific changes, and the
update service refuses to run rather than overwriting it.

## Supported versions

Only the tip of `main`. There are no maintained release branches, and the appliance
follows the repository rather than a version number.
