#!/usr/bin/env bash
# Boot an ISO under QEMU and report whether the image reached userspace - and, when a second
# marker is given, whether the graphical session came up on top of it.
#
#   MARKER unset   interactive: the terminal is handed to QEMU, for a human.
#   MARKER set     QEMU runs detached, the script waits for the marker on the serial
#                  console, kills QEMU, and exits non-zero if the deadline passes first.
#
# SECOND_MARKER is waited for after MARKER, within the same boot and the same deadline. The
# order is the assertion: a session marker that arrived before userspace would mean
# something other than the session wrote it, and a second run would cost another boot to
# learn less.
#
# The exit status is the point: `nix build` on the check that drives this either succeeds,
# meaning the image booted, or fails with the serial log attached.
set -uo pipefail

ISO="${ISO:?ISO must point to an image to boot}"
MODE="${MODE:-bios}"
MACHINE="${MACHINE:-q35}"
MEM="${MEM:-2048}"
CPUS="${CPUS:-2}"
MARKER="${MARKER:-}"
SECOND_MARKER="${SECOND_MARKER:-}"
TIMEOUT="${TIMEOUT:-900}"
RENDER_NODE="${RENDER_NODE:-}"
OVMF_FIRMWARE="${OVMF_FIRMWARE:-}"

if [ -z "${QEMU:-}" ]; then
  echo "QEMU not set" >&2
  exit 2
fi

args=(-machine "$MACHINE" -m "$MEM" -smp "$CPUS" -no-reboot -cdrom "$ISO")

# QEMU's default VGA is a bochs card mesa has no driver for, and the compositor skips
# software EGL renderers, so without a GPU the session comes up *headless*: it answers on
# its socket while nothing is drawn. A DRM render node on the host is what gives the guest a
# virtio_gpu the compositor will render on, and `-display egl-headless` needs one - a
# GPU-less CI runner falls back to -nographic. With a display frontend the serial console
# must be asked for, since -nographic no longer provides it, and it is the only channel read
# here.
if [ -n "$RENDER_NODE" ]; then
  args+=(-device virtio-vga-gl -display egl-headless -serial mon:stdio)
else
  args+=(-nographic)
fi

# KVM is the difference between seconds and tens of minutes. Without it QEMU falls back to
# software emulation, slow enough that the boot test times out instead of failing - so say
# which one is happening.
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
  if [ -z "$OVMF_FIRMWARE" ]; then
    echo "OVMF_FIRMWARE required in efi mode" >&2
    exit 2
  fi
  # pkgs.OVMF.firmware is the OVMF_CODE.fd file itself, not a directory holding one.
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
    # Nothing to wait for beyond the first marker: kill QEMU now rather than spend the rest
    # of the deadline watching a boot that has already proved its point.
    if [ -z "$SECOND_MARKER" ]; then break; fi
  fi
  if [ "$found" = 1 ] && [ -n "$SECOND_MARKER" ] &&
    grep -q -- "$SECOND_MARKER" "$log" 2>/dev/null; then
    second=1
    break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then break; fi
  sleep 5
done

# Ask politely, then insist: a QEMU left alive holds the kvm device and the next run behaves
# strangely.
kill -TERM "$qpid" 2>/dev/null
for _ in 1 2 3 4 5; do
  kill -0 "$qpid" 2>/dev/null || break
  sleep 1
done
kill -KILL "$qpid" 2>/dev/null
wait "$qpid" 2>/dev/null

if [ "$found" = 1 ] && { [ -z "$SECOND_MARKER" ] || [ "$second" = 1 ]; }; then
  if [ -n "$SECOND_MARKER" ]; then
    # A session marker with `outputs=0` is a compositor with nowhere to draw. Where the
    # sandbox could hand it a GPU that is a failure, because the desktop is the product.
    # Where it could not, "OK" about a headless session would be the same false green this
    # check exists to prevent, so it is reported as a limit instead of a pass.
    if [ -z "$RENDER_NODE" ]; then
      echo "NOTE: session asserted without a GPU - no render node here, so the compositor runs" >&2
      echo "      headless and 'draws something' is NOT what this run proved." >&2
    elif ! grep -Eq -- "$SECOND_MARKER.*outputs=[1-9]" "$log"; then
      echo "FAILURE: '$SECOND_MARKER' seen but the session reports no output (mode $MODE)" >&2
      echo "         the compositor answers and draws nothing; see the marker line below." >&2
      grep -- "$SECOND_MARKER" "$log" | tail -3 >&2
      exit 1
    fi
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
