# Guard rail: an image must not drift in size without anyone noticing.
#
# Same instrument as the sibling project depannix (nix/closure-manifest.nix and
# docs/budget.md there, nix/size-budget.nix here): a measured ceiling per flavour,
# with the reason for the number written down. The figures are in docs/budget.md,
# and each one is a measurement, never an estimate.
#
# This exists because the release pipeline has a hard external ceiling - GitHub
# refuses any release asset of 2 GiB or more - and the installer image is twice
# that. It ships in parts as a result (see .github/workflows/release.yml). A budget
# is what turns "the image grew" from a surprise discovered at the last step of a
# 40-minute release job into a red check on the commit that caused it.
{
  pkgs,
  image,
  flavour,
  budgetMiB,
}:

pkgs.runCommand "easy-nix-size-budget-${flavour}" { } ''
  iso="$(find ${image}/iso -name '*.iso' | head -1)"
  if [ -z "$iso" ]; then
    echo "FAIL: no ISO under ${image}/iso, so there is nothing to measure." >&2
    exit 1
  fi
  size=$(stat -c%s "$iso")
  budget=$(( ${toString budgetMiB} * 1024 * 1024 ))
  printf 'flavour=%s size=%s bytes (%s MiB), budget=%s bytes (%s MiB)\n' \
    "${flavour}" "$size" "$((size / 1048576))" "$budget" "$((budget / 1048576))"
  if [ "$size" -gt "$budget" ]; then
    echo "FAIL: the ${flavour} image exceeds its size budget." >&2
    echo "See docs/budget.md. Adding an application without measuring its closure is" >&2
    echo "the usual cause; the number is a measurement, so re-measure it knowingly." >&2
    exit 1
  fi
  echo "OK" > $out
''
