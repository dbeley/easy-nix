# shellcheck shell=bash
#
# Report, on the serial console, that the graphical session came up - and that it is a
# Wayland one.
#
# Why a script inside the session rather than an assertion made from outside: only
# something *in* the session can see the session's own environment. XDG_SESSION_TYPE and
# WAYLAND_DISPLAY here are the compositor's, not ours, so this is evidence rather than a
# self-declaration.
#
# Why it asks the compositor a question instead of looking for a process: `wayland-info`
# connects to the Wayland socket as an ordinary client and enumerates the globals. A
# reply proves the compositor answers clients; a live process proves only that it
# started, and a compositor that started and then failed to open a device is a black
# screen with a running process behind it.
#
# `wayland-info` and not the previous `niri msg`: labwc has no IPC socket of its own, and
# `wlr-randr` would depend on a protocol labwc is free not to implement. Every Wayland
# compositor has to advertise its outputs as `wl_output` globals, so counting those is
# the one question that survives changing the compositor - which is exactly what happened
# here, and the boot test asserts on the answer.
#
# Run as a systemd user service bound to `graphical-session.target`, which the session's
# own autostart brings up (see modules/desktop/labwc.nix). labwc owns no tty of ours, so
# the marker is written to /dev/ttyS0 by name: /dev/console is not reliable here, since
# which device it points at depends on the order of the `console=` arguments, and a
# marker written to the wrong one makes a working session look dead to the boot test.
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
info=""
until info="$(wayland-info 2>/dev/null)" && [ -n "$info" ]; do
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

if [ -n "$info" ]; then
  # One line per global, of the form `interface: 'wl_output', version: 4, name: 3`. A
  # session with zero outputs draws nothing, so the count is reported next to the marker
  # rather than asserted here: on a machine with no display attached, zero is the honest
  # answer and not a failure of the session. The boot test decides whether zero is
  # acceptable, because only it knows whether it gave the guest a device to draw on.
  outputs="$(printf '%s\n' "$info" | grep -c "interface: 'wl_output'" || true)"
  report "EASY_NIX_SESSION type=${XDG_SESSION_TYPE:-unknown} display=${WAYLAND_DISPLAY:-none} session=${XDG_CURRENT_DESKTOP:-unknown} outputs=${outputs:-0}"
else
  report "EASY_NIX_SESSION failed compositor-unreachable display=${WAYLAND_DISPLAY:-none}"
  exit 1
fi
