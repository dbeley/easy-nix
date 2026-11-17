# Contributing

## What this project is

A NixOS distribution: a flake that builds a bootable installer ISO, a self-updating
installed system, and an experimental ARM SD-card image. It is not a Nix helper library
and it exposes no library API. A patch that adds a command-line convenience for Nix itself
belongs in another project.

## Before you write anything

Read `AGENTS.md`. It lists the rules the project does not trade away, and the pitfalls
that have already cost time here. Two of them are worth repeating because they are the
most common reason a first patch is rejected:

1. **Wayland only.** `services.xserver.enable` is asserted false. An application that needs
   an X server goes through `xwayland-satellite`.
2. **An update never destroys the operator's work.** `git merge --ff-only`, never
   `reset --hard`, and stop with a notification instead of resolving a conflict by force.

## Setting up

```sh
git clone https://github.com/dbeley/easy-nix
cd easy-nix
nix develop          # the checks, nixos-rebuild, qemu for the boot tests
```

`direnv` users get the same shell from the `.envrc`.

## Testing a change

Run what CI runs. `AGENTS.md` has the gates, in increasing order of cost, with what each
one proves and the KVM requirement the boot tests cannot do without; `justfile` is the
short version: `nix fmt`, `just check`, `just eval`, `just test-light`.

## Scope

Welcome:

- a new application module under `modules/apps/`, if it is something a desktop needs;
- a fix to the appliance layer (`modules/appliance/`) that keeps the update path
  non-destructive;
- ARM board support: the `sd-card` flavour is accepted as experimental, and a board
  profile for something other than a Raspberry Pi 4/5 is useful;
- tightening the installer, particularly the refusal paths.

Out of scope, and a patch adding them will be declined:

- a graphical installer: the ISO ships a scripted one on purpose;
- non-Wayland sessions, a display manager, or a second desktop environment;
- disk encryption as a default (it is a change to `modules/disk-layout.nix` plus one line
  in the installer, and it is documented as absent rather than half-done);
- wrappers that hide Nix from the user.

## Conventions

- **Content in English**, including comments, commit messages, workflow step names and
  artifact names.
- **No em dash (U+2014) anywhere in prose.** Write `" - "` instead. A repository-wide
  search for the character must come back empty.
- **Comment the decision, not the code.** The interesting part of a module here is usually
  why an option is set where it is set.
- One commit per intent, and say in the message what the change does to an appliance that
  already exists.

## Licence

MIT. By contributing you agree your work is released under the same terms. See `LICENSE`,
which also credits nixbook, whose design this project starts from.
