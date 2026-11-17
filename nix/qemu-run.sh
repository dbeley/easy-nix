#!/usr/bin/env bash
# Boot an ISO under QEMU and report whether the image reached userspace, and - when a
# second marker is given - whether the graphical session came up on top of it.
#
# Two modes in one script:
#   - MARKER unset: interactive, the terminal is handed to QEMU. For a human.
#   - MARKER set: QEMU runs detached, the script waits for the marker to appear on the
#     serial console, kills QEMU, and exits non-zero if the deadline passes first.
#
# SECOND_MARKER, when set, is waited for *after* MARKER, within the same boot and the
# same deadline. The order is the assertion: a session marker that arrives before
# userspace would mean the marker is being written by something other than the session,
# and a separate run would cost another boot to learn less.
#
# RENDER_NODE, when set to a DRM render node the sandbox can see, gives the guest a GPU
# the compositor actually renders on, and turns the session assertion into "the session
# has an output". Without one - a CI runner - the guest has nothing to draw on, the
# session comes up headless, and the harness says so rather than counting that as a pass.
#
# The exit status is the whole point: `nix build` on the check that drives this either
# succeeds, meaning the image booted, or fails with the serial log attached.
set -uo pipefail

ISO="${ISO:?ISO must point to an image to boot}"
MODE="${MODE:-bios}"
MACHINE="${MACHINE:-q35}"
MEM="${MEM:-2048}"
CPUS="${CPUS:-2}"
MARKER="${MARKER:-}"
SECOND_MARKER="${SECOND_MARKER:-}"
TIMEOUT="${TIMEOUT:-900}"

[ -n "${QEMU:-}" ] || {
  echo "QEMU not set" >&2
  exit 2
}

args=(-machine "$MACHINE" -m "$MEM" -smp "$CPUS" -no-reboot -cdrom "$ISO")

# The guest's GPU, when this environment can give it one.
#
# QEMU's default VGA is a bochs card that mesa has no driver for, and the compositor skips
# software EGL renderers: the compositor then comes up *headless*. It answers on its
# socket, so a test that only greps for the session marker passes while nothing is
# drawn - which is exactly how a desktop that never appeared shipped.
#
# `-display egl-headless` needs a DRM render node on the *host*, so this is conditional:
# a GPU-less CI runner has none. When RENDER_NODE is set, the guest gets virgl (a
# virtio_gpu a compositor will render on) and the marker below has to report an output; when it
# is not, the session marker is the only claim the test makes, and the harness says so
# out loud instead of implying more.
if [ -n "${RENDER_NODE:-}" ]; then
  args+=(-device virtio-vga-gl -display egl-headless)
  # `-nographic` used to provide the serial console as a side effect; with a display
  # frontend it has to be asked for, and it is the only channel the test reads.
  args+=(-serial mon:stdio)
else
  args+=(-nographic)
fi

# KVM is the difference between seconds and tens of minutes. Without it QEMU falls back
# to software emulation, which is slow enough that the boot test times out rather than
# fails - so say which one is happening.
if [ -w /dev/kvm ]; then
  args+=(-enable-kvm -cpu host)
  echo "[qemu] KVM enabled" >&2
else
  args+=(-cpu max)
  echo "[qemu] KVM unavailable - software emulation, this will be slow" >&2
fi

case "$MODE" in
bios) ;;
efi)
  [ -n "${OVMF_FIRMWARE:-}" ] || {
    echo "OVMF_FIRMWARE required in efi mode" >&2
    exit 2
  }
  args+=(-drive "if=pflash,format=raw,readonly=on,file=$OVMF_FIRMWARE")
  ;;
*)
  echo "unknown MODE: $MODE" >&2
  exit 2
  ;;
esac

if [ -z "$MARKER" ]; then
  exec "$QEMU" "${args[@]}"
fi

log="serial.log"
: >"$log"
"$QEMU" "${args[@]}" >>"$log" 2>&1 &
qpid=$!

deadline=$(($(date +%s) + TIMEOUT))
found=0
second=0
while kill -0 "$qpid" 2>/dev/null; do
  if [ "$found" = 0 ] && grep -q -- "$MARKER" "$log" 2>/dev/null; then
    found=1
    # Nothing to wait for beyond the first marker: kill QEMU now rather than spend the
    # rest of the deadline watching a boot that has already proved its point.
    [ -n "$SECOND_MARKER" ] || break
  fi
  if [ "$found" = 1 ] && [ -n "$SECOND_MARKER" ] &&
    grep -q -- "$SECOND_MARKER" "$log" 2>/dev/null; then
    second=1
    break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    break
  fi
  sleep 5
done

# Ask politely, then insist: a QEMU left alive holds the kvm device and the next run
# behaves strangely.
kill -TERM "$qpid" 2>/dev/null
for _ in 1 2 3 4 5; do
  kill -0 "$qpid" 2>/dev/null || break
  sleep 1
done
kill -KILL "$qpid" 2>/dev/null
wait "$qpid" 2>/dev/null

if [ "$found" = 1 ] && { [ -z "$SECOND_MARKER" ] || [ "$second" = 1 ]; }; then
  # A session marker with `outputs=0` is a compositor with nowhere to draw. Where the
  # sandbox could hand it a GPU, that is a failure, not a detail: the desktop is the
  # product. Where it could not (no render node on the host), saying "OK" about a
  # headless session would be the same false green this check exists to prevent, so it
  # is reported as a limit instead of as a pass.
  if [ -n "$SECOND_MARKER" ] && [ -n "${RENDER_NODE:-}" ] &&
    ! grep -Eq -- "$SECOND_MARKER.*outputs=[1-9]" "$log"; then
    echo "FAILURE: '$SECOND_MARKER' seen but the session reports no output (mode $MODE)" >&2
    echo "         the compositor answers and draws nothing; see the marker line below." >&2
    grep -- "$SECOND_MARKER" "$log" | tail -3 >&2
    exit 1
  fi
  if [ -n "$SECOND_MARKER" ] && [ -z "${RENDER_NODE:-}" ]; then
    echo "NOTE: session asserted without a GPU - no render node here, so the compositor runs" >&2
    echo "      headless and 'draws something' is NOT what this run proved." >&2
  fi
  echo "OK: marker seen (mode $MODE)"
  if [ -n "$SECOND_MARKER" ]; then
    echo "OK: second marker seen (mode $MODE)"
  fi
  exit 0
fi

if [ "$found" = 1 ]; then
  echo "FAILURE: '$MARKER' seen but '$SECOND_MARKER' not after ${TIMEOUT}s (mode $MODE)" >&2
  echo "         userspace came up; the graphical session did not report itself." >&2
else
  echo "FAILURE: marker not seen after ${TIMEOUT}s (mode $MODE)" >&2
fi
echo "--- last 40 lines of $log ---" >&2
tail -40 "$log" >&2
exit 1
