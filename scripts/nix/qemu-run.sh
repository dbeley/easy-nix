#!/usr/bin/env bash
# Boot an ISO under QEMU and report whether the image reached userspace.
#
# Two modes in one script:
#   - MARKER unset: interactive, the terminal is handed to QEMU. For a human.
#   - MARKER set: QEMU runs detached, the script waits for the marker to appear on the
#     serial console, kills QEMU, and exits non-zero if the deadline passes first.
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
TIMEOUT="${TIMEOUT:-900}"

[ -n "${QEMU:-}" ] || {
  echo "QEMU not set" >&2
  exit 2
}

args=(-machine "$MACHINE" -m "$MEM" -smp "$CPUS" -nographic -no-reboot -cdrom "$ISO")

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
while kill -0 "$qpid" 2>/dev/null; do
  if grep -q -- "$MARKER" "$log" 2>/dev/null; then
    found=1
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

if [ "$found" = 1 ]; then
  echo "OK: marker seen (mode $MODE)"
  exit 0
fi

echo "FAILURE: marker not seen after ${TIMEOUT}s (mode $MODE)" >&2
echo "--- last 40 lines of $log ---" >&2
tail -40 "$log" >&2
exit 1
