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
MARKER_FAILED="${MARKER_FAILED:-EASY_NIX_INSTALL_FAILED}"
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
  # The network, because this medium is the light one: it carries the flake and its inputs
  # but not the system it installs, so `nixos-install` has to fetch or build that. With no
  # network device the guest resolves no names at all and the install dies on "Could not
  # resolve host: github.com", with the disk already partitioned, formatted and mounted -
  # which reads like a flake problem and is a missing network card. The value is quoted
  # because of its comma: unquoted, shellcheck reads it as an array element separator.
  -nic "user,model=virtio-net-pci"
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

wait_for() { # wait_for <log> <marker> <seconds> [marker that means the run is over]
  # Returns 0 when the marker appears, 2 when the run is over without it, 1 on the
  # deadline. The distinction matters: an unattended install that refuses something ends
  # in seconds, and waiting out a forty-five-minute deadline to report it turns a fast
  # diagnosis into a slow one.
  #
  # "Over" covers both ways a guest can stop trying: it said why, or it is simply gone.
  # Both are needed. Watching only the process misses nothing when the machine is still
  # up and refusing; watching only the marker reports a guest that died before it could
  # write one. And the process check cannot be `kill -0`: a finished child that nothing
  # has reaped is a zombie, on which `kill -0` succeeds, so ask for its state.
  local log="$1" marker="$2" deadline=$((SECONDS + $3))
  local failure="${4:-}"
  while [ "$SECONDS" -lt "$deadline" ]; do
    if grep -q -- "$marker" "$log" 2>/dev/null; then
      return 0
    fi
    if [ -n "$failure" ] && grep -q -- "$failure" "$log" 2>/dev/null; then
      return 2
    fi
    # `/proc` and shell builtins only. An earlier version asked `ps` for the process state,
    # to tell a running child from a zombie that `kill -0` cannot distinguish - and `ps`
    # belongs to procps, which the sandbox that runs this does not carry. The check then
    # failed four milliseconds in, before the virtual machine had finished starting, and it
    # failed on a machine whose shell has `ps` and passed on the one that does not. There is
    # no external command here to be missing.
    state=""
    if [ -r "/proc/$qemu_pid/stat" ]; then
      # stat is one line with no trailing newline, so `read` reports failure on it while
      # still setting the variable - hence the `|| true`, and no `while`.
      read -r line <"/proc/$qemu_pid/stat" || true
      # The state is the field after the command name. That name is in parentheses and may
      # contain spaces, so take everything after the LAST ") " and then up to the next
      # space. Chopping at the first space of " R 1 1234 ..." yields the empty string, which
      # this function reads as "the machine is gone" - and it then failed three
      # milliseconds after starting a virtual machine that was booting perfectly.
      state="${line##*) }"
      state="${state%% *}"
    fi
    case "$state" in
    '' | Z*) return 2 ;;
    esac
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
  # What the guest said about the installer comes first, because the interesting
  # failure is usually an early refusal and not the last thing the kernel printed.
  # Printing it here is the only way it reaches the CI log: a build that fails has its
  # output directory discarded, so copying the log into $out would be lost.
  echo "--- what the guest said about the installer ---" >&2
  grep -aE "easy-nix-autoinstall|easy-nix-install|EASY_NIX_INSTALLED|EASY_NIX_INSTALL_FAILED|not a block device|About to ERASE|partitioning|nixos-install|Error|error:" "$1" | tail -40 >&2 || true
  echo "--- last 60 lines of $1 ---" >&2
  tail -60 "$1" >&2 || true
  kill "$qemu_pid" 2>/dev/null
  exit 1
}

echo "==> boot 1: the medium installs onto $disk (up to ${TIMEOUT_INSTALL}s)" >&2
run_qemu install.log -cdrom "$ISO"
if wait_for install.log "$MARKER_INSTALLED" "$TIMEOUT_INSTALL" "$MARKER_FAILED"; then
  echo "[install-test] the installer finished" >&2
else
  rc=$?
  if [ "$rc" = 2 ]; then
    fail install.log "the medium never reported $MARKER_INSTALLED: it said $MARKER_FAILED, or it stopped before saying either - its own words are above"
  fi
  fail install.log "the installer never reported $MARKER_INSTALLED within ${TIMEOUT_INSTALL}s"
fi
kill "$qemu_pid" 2>/dev/null
wait "$qemu_pid" 2>/dev/null

echo "==> boot 2: the installed system starts on its own (up to ${TIMEOUT_BOOT}s)" >&2
run_qemu boot.log
if wait_for boot.log "$MARKER_BOOTED" "$TIMEOUT_BOOT"; then
  echo "[install-test] the installed system reached userspace" >&2
else
  rc=$?
  if [ "$rc" = 2 ]; then
    fail boot.log "the installed system stopped without reporting $MARKER_BOOTED - nothing was written by the medium on this boot, so the log above is the installed machine's"
  fi
  fail boot.log "the installed system never reported $MARKER_BOOTED within ${TIMEOUT_BOOT}s"
fi
kill "$qemu_pid" 2>/dev/null

echo "[install-test] OK: partitioned, installed, and booted" >&2
