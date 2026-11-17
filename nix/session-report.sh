# shellcheck shell=bash
#
# Report, on the serial console, that the graphical session came up - and that it is a
# Wayland one.
#
# Why a script inside the session rather than an assertion made from outside: only
# something *in* the session can see the session's own environment. XDG_SESSION_TYPE and
# WAYLAND_DISPLAY here are niri's, not ours, so this is evidence rather than a
# self-declaration.
#
# Why it asks the compositor a question instead of looking for a process: `niri msg`
# connects to niri's socket, so a reply proves the compositor answers a client, where a
# live process proves only that it started. That distinction is the whole point - a niri
# that started and then failed to open a device is a black screen with a running process
# behind it.
#
# Run as a systemd user service bound to `graphical-session.target`, which niri-session
# brings up (see modules/desktop/niri.nix). niri owns no tty, so the marker is written to
# /dev/ttyS0 by name: /dev/console is not reliable here, since which device it points at
# depends on the order of the `console=` arguments, and a marker written to the wrong one
# makes a working session look dead to the boot test.
#
# The boot test greps for the first word of the line this prints (`EASY_NIX_SESSION`).
#
# No shebang and no `set` line: pkgs.writeShellApplication supplies the first and
# `set -euo pipefail`, and runs ShellCheck over this text at build time - which is why
# the `shell=bash` directive above is there: without it, a file with no shebang is a file
# whose shell ShellCheck cannot guess.

# A compositor that answers on the first frame can still be about to answer on the
# second, and a session report that is one second early would be a flaky test. Bounded,
# so a session that never comes up fails with this script's own message rather than
# hanging.
deadline=$(($(date +%s) + 60))
until niri msg version >/dev/null 2>&1; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    break
  fi
  sleep 1
done

report() {
  printf '%s\n' "$*"
  # The console is the only channel a machine with no display has, and the boot test
  # reads nothing else. Absent or unwritable is not fatal: the journal still has the
  # line, which is what a human debugging the check reads.
  if [ -w /dev/ttyS0 ]; then
    printf '%s\n' "$*" >/dev/ttyS0
  fi
  return 0
}

if niri msg version >/dev/null 2>&1; then
  # `niri msg outputs` prints one block per output, each starting with "Output ". A
  # session with zero outputs draws nothing, so the count is reported next to the marker
  # rather than asserted here: on a machine with no display attached, zero is the honest
  # answer and not a failure of the session.
  outputs="$(niri msg outputs 2>/dev/null | grep -c '^Output' || true)"
  report "EASY_NIX_SESSION type=${XDG_SESSION_TYPE:-unknown} display=${WAYLAND_DISPLAY:-none} session=${XDG_CURRENT_DESKTOP:-niri} outputs=${outputs:-0}"
else
  report "EASY_NIX_SESSION failed compositor-unreachable display=${WAYLAND_DISPLAY:-none}"
  exit 1
fi
