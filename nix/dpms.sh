# shellcheck shell=bash
#
# Turn every output off, or back on; `swayidle` calls this after ten idle minutes and on the
# first activity.
#
# A script rather than a one-liner in the unit because `wlopm` takes an output name and no
# wildcard, and the name is the compositor's to choose ("Virtual-1" in a VM, "eDP-1" on a
# laptop). So ask the compositor which outputs exist and hand each name over.
# `wlr-randr` prints the name first and unindented on each output's line, the details
# indented; a session with no output simply does nothing.
#
# No shebang and no `set`: pkgs.writeShellApplication supplies both, and the `shell=bash`
# directive above is what lets ShellCheck parse a file without a shebang.

mode="${1:-}"
case "$mode" in
on | off) ;;
*)
  printf 'usage: %s on|off\n' "$0" >&2
  exit 2
  ;;
esac

outputs="$(wlr-randr 2>/dev/null | grep -E '^[^[:space:]]' | cut -d' ' -f1 || true)"

for output in $outputs; do
  # A compositor that refuses output power management is not worth failing on: the screen
  # stays lit, which is what it was doing before.
  wlopm "--$mode" "$output" >/dev/null 2>&1 || true
done
