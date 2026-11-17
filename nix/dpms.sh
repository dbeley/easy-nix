# shellcheck shell=bash
#
# Turn every output off, or back on. `swayidle` calls this after ten idle minutes and on
# the first activity.
#
# Why a script and not a one-liner in the unit: `wlopm` takes an output name and no
# wildcard, and a compositor is free to name its outputs anything ("Virtual-1" in a VM,
# "eDP-1" on a laptop, "HDMI-A-1" on a desk). So ask the compositor which outputs exist
# and hand each name over, rather than guessing one.
#
# `wlr-randr` prints one line per output, the name first and unindented; the detail lines
# below it are indented. Name the first field of every unindented line, and a session
# with no output (a machine with no display) simply does nothing.
#
# No shebang and no `set` line: pkgs.writeShellApplication supplies both, and the
# `shell=bash` directive above is what lets ShellCheck parse a file without a shebang.

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
  # A compositor that refuses output power management is not an error worth failing on:
  # the screen simply stays lit, which is what it was doing before.
  wlopm "--$mode" "$output" >/dev/null 2>&1 || true
done
