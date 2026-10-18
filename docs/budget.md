# Size budget

An image that grows without anyone noticing is an image whose documentation quietly
stops being true. This project therefore measures its images and keeps a ceiling per
flavour, checked by `nix build .#packages.x86_64-linux.size-budget-<flavour>` - the
same instrument the sibling project depannix uses, with its own numbers.

Every figure below is a **measurement of a real artifact**, not a sum of package sizes.
A package list is a ranking; it is not a budget.

## Measured, at v0.1.0 (2026-10-18)

| Flavour | What it is | Measured | Budget | Margin |
|---|---|---|---|---|
| `installer` | the bootable medium, applications included | 4 035 411 968 B (3848 MiB) | 4100 MiB | 251 MiB (6.5%) |
| `test` | the deliberately light live image used by the boot test | 1 979 711 488 B (1888 MiB) | 2048 MiB | 160 MiB (8.5%) |

Re-measure with:

```sh
nix build .#packages.x86_64-linux.size-budget-installer -L   # prints size and budget
nix build .#packages.x86_64-linux.size-budget-test -L
```

The check fails when an image crosses its ceiling, and names the flavour it measured.
A guard that never fires is not a guard: both of these have run on the artifacts above.

## Why the installer image is larger than a release asset may be

GitHub refuses any release asset of 2 GiB or more. The installer is nearly twice that,
and the excess is not padding: it is the applications themselves (browsers, office
suite, Steam), which is what lets an installation work **without the network**. Removing
them would trade a documented capability for a smaller download.

The answer is not to shrink the image but to ship it in parts of 1900 MiB, which the
release workflow does, with the assembled image attested as one file. The budget above
is therefore not a limit imposed by the asset cap - it is a drift detector. When it
fires, the question is "what did we add, and do we mean it?", answered by measuring a
content change against two closure manifests.

## What has no budget

- **The ARM SD-card image.** CI only *evaluates* the aarch64 configuration and no board
  has been flashed, so there is no measured size to hold it to. Writing a budget from a
  guess would be worse than having none: it would look measured. The first person to
  build the image on real hardware should measure it here.
- **The appliance's own closure.** It is what an installed machine runs, so its manifest
  is published, but it is not an image with a size of its own; it is bounded by the
  medium that carries it.

## The rule

Adding an application means adding its closure, and the closure is almost never the size
of the package. Measure the image, update this table with the new figure and the reason,
and only then move the ceiling.
