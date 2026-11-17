# shellcheck shell=bash
#
# Report, on the serial console, that the graphical session came up - and that it is a
# Wayland one.
#
# It runs inside the session because only a process there sees the compositor's own
# XDG_SESSION_TYPE and WAYLAND_DISPLAY, so this is evidence rather than a self-declaration.
# And it asks the compositor a question - `wayland-info` connects as an ordinary client and
# enumerates the globals - rather than looking for its process: a compositor that started
# and then failed to open a device is a black screen with a live process behind it. Counting
# `wl_output` globals is the one question that survives a change of compositor.
#
# Started by `graphical-session.target` (see modules/desktop/labwc.nix). The marker is
# written to /dev/ttyS0 by name: /dev/console depends on the order of the `console=`
# arguments, and a marker written to the wrong one makes a working session look dead to the
# boot test, which greps for `EASY_NIX_SESSION`.
#
# No shebang and no `set`: pkgs.writeShellApplication supplies both. The `shell=bash` above
# is a directive, not a comment - without it ShellCheck cannot guess the shell of a file
# that has no shebang.
#
# A compositor that answers on the first frame can still be about to answer on the second,
# and a report one second early would be a flaky test. Bounded, so a session that never
# comes up fails with this script's own message rather than hanging.
deadline=$(($(date +%s) + 60))
info=""
until info="$(wayland-info 2>/dev/null)" && [ -n "$info" ]; do
  if [ "$(date +%s)" -ge "$deadline" ]; then break; fi
  sleep 1
done

report() {
  printf '%s\n' "$*"
  # The console is the only channel a machine with no display has. Absent or unwritable is
  # not fatal: the journal still has the line a human will read.
  if [ -w /dev/ttyS0 ]; then
    printf '%s\n' "$*" >/dev/ttyS0
  fi
}

if [ -n "$info" ]; then
  # One line per global, of the form `interface: 'wl_output', version: 4, name: 3`. Zero
  # outputs draws nothing, but on a machine with no display that is the honest answer, so
  # the count is reported next to the marker and the boot test decides whether zero is
  # acceptable - only it knows whether the guest was given a device to draw on.
  outputs="$(printf '%s\n' "$info" | grep -c "interface: 'wl_output'" || true)"
  report "EASY_NIX_SESSION type=${XDG_SESSION_TYPE:-unknown} display=${WAYLAND_DISPLAY:-none} session=${XDG_CURRENT_DESKTOP:-unknown} outputs=${outputs}"
else
  report "EASY_NIX_SESSION failed compositor-unreachable display=${WAYLAND_DISPLAY:-none}"
  exit 1
fi
