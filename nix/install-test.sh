#!/usr/bin/env bash
# Install, then boot what was installed.
#
# Two boots, because they answer two questions a single run cannot:
#
#   1. did the installer partition a disk and put a system on it? The medium used here
#      installs itself at boot (`easyNix.autoInstall`) and writes EASY_NIX_INSTALLED on
#      the serial console when it is done;
#   2. does that system start on its own? The second boot has no medium attached, so
#      anything on the console comes from the installed machine, which writes
#      EASY_NIX_READY when it reaches userspace.
#
# Nothing here needs a screen: `easy-nix-install --disk ... --yes` asks nothing, and
# both markers are written to /dev/ttyS0 explicitly, never to /dev/console, whose target
# depends on the order of the `console=` arguments.
#
# The exit status is the whole point. `nix build` on the check that drives this either
# succeeds - meaning a disk was partitioned, installed onto, and booted - or fails with
# both serial logs attached.
set -uo pipefail

: "${ISO:?ISO must point to the medium to install from}"
: "${QEMU:?QEMU must point to a qemu binary}"
: "${OVMF_FIRMWARE:?OVMF_FIRMWARE must point to OVMF_CODE.fd}"

MARKER_INSTALLED="${MARKER_INSTALLED:-EASY_NIX_INSTALLED}"
MARKER_BOOTED="${MARKER_BOOTED:-EASY_NIX_READY}"
TIMEOUT_INSTALL="${TIMEOUT_INSTALL:-1800}"
TIMEOUT_BOOT="${TIMEOUT_BOOT:-600}"
DISK_SIZE="${DISK_SIZE:-24G}"
MEM="${MEM:-4096}"
CPUS="${CPUS:-4}"

disk="disk.img"
# Sparse: the test only pays for what the install writes.
qemu-img create -f raw "$disk" "$DISK_SIZE" >/dev/null

args=(
  -machine q35
  -m "$MEM"
  -smp "$CPUS"
  -nographic
  # `pkgs.OVMF.firmware` is the code file itself, not a directory holding one.
  -drive "if=pflash,format=raw,readonly=on,file=$OVMF_FIRMWARE"
  -drive "file=$disk,if=virtio,format=raw"
)

# KVM is the difference between minutes and hours. Without it this test does not fail,
# it times out - so say which one is happening.
if [ -w /dev/kvm ]; then
  args+=(-enable-kvm -cpu host)
  echo "[install-test] KVM enabled" >&2
else
  args+=(-cpu max)
  echo "[install-test] KVM unavailable - software emulation, this will be very slow" >&2
fi

wait_for() { # wait_for <log> <marker> <seconds>
  local log="$1" marker="$2" deadline=$((SECONDS + $3))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if grep -q -- "$marker" "$log" 2>/dev/null; then
      return 0
    fi
    sleep 5
  done
  return 1
}

run_qemu() { # run_qemu <log> [extra args...]
  local log="$1"
  shift
  : >"$log"
  "$QEMU" "${args[@]}" "$@" >>"$log" 2>&1 &
  qemu_pid=$!
}

fail() { # fail <log> <message>
  echo "[install-test] FAIL: $2" >&2
  echo "--- last lines of $1 ---" >&2
  tail -40 "$1" >&2 || true
  kill "$qemu_pid" 2>/dev/null
  exit 1
}

echo "==> boot 1: the medium installs onto $disk (up to ${TIMEOUT_INSTALL}s)" >&2
run_qemu install.log -cdrom "$ISO"
if wait_for install.log "$MARKER_INSTALLED" "$TIMEOUT_INSTALL"; then
  echo "[install-test] the installer finished" >&2
else
  fail install.log "the installer never reported $MARKER_INSTALLED"
fi
kill "$qemu_pid" 2>/dev/null
wait "$qemu_pid" 2>/dev/null

echo "==> boot 2: the installed system starts on its own (up to ${TIMEOUT_BOOT}s)" >&2
run_qemu boot.log
if wait_for boot.log "$MARKER_BOOTED" "$TIMEOUT_BOOT"; then
  echo "[install-test] the installed system reached userspace" >&2
else
  fail boot.log "the installed system never reported $MARKER_BOOTED"
fi
kill "$qemu_pid" 2>/dev/null

echo "[install-test] OK: partitioned, installed, and booted" >&2
