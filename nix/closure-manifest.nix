# Composition manifest: the exhaustive list of store paths a system is made of, with their
# hashes. This is what makes "you can check what you downloaded" verifiable - a third party
# can compare it against their own store, or against cache.nixos.org, without trusting
# whoever ran the build.
#
# The data comes from Nix itself: `exportReferencesGraph` injects the complete graph as JSON
# into `$NIX_ATTRS_JSON_FILE` at instantiation time. Not `nix path-info`, which needs the
# store database and is refused by the sandbox - this is what `closureInfo` does too.
{
  pkgs,
  toplevel,
  flavour,
}:

let
  # The closure differs per flavour and per architecture, so every file name carries both -
  # otherwise the manifests collide, and a reader cannot tell which image they verify.
  system = pkgs.stdenv.hostPlatform.system;
  suffix = "${flavour}-${system}";

  # Filters and prose live in their own files rather than inline: inside a Nix `''` string
  # every apostrophe would have to be written `'''`.
  jsonFilter = pkgs.writeText "easy-nix-closure.jq" ''
    .easyNix
    | map({path, narHash, narSize, references})
    | sort_by(.path)
  '';

  pathsFilter = pkgs.writeText "easy-nix-paths.jq" ''
    .easyNix[].path
  '';

  # Exact format expected by `nix-store --load-db`.
  registrationFilter = pkgs.writeText "easy-nix-registration.jq" ''
    .easyNix
    | map([.path, .narHash, .narSize, "", (.references | length)] + .references)
    | add
    | map("\(.)\n")
    | add
  '';

  sizeFilter = pkgs.writeText "easy-nix-total.jq" ''
    .easyNix | map(.narSize) | add
  '';

  readme = pkgs.writeText "easy-nix-readme.txt" ''
    Checking the easy-nix ${flavour} closure for ${system}
    =====================================================

    This set describes the ${flavour} image for ${system} and no other; everything in it is
    named after both, because the closure differs between flavours and architectures.

    1. Hashes come in two encodings, so no conversion is needed:

         - `closure-${suffix}.json` -> `.narHash`, in Nix base32 (`sha256:...`);
         - `closure-sri-${suffix}.tsv` -> column 2, in SRI/base64 (`sha256-...=`), the
           format narinfo files use.

       Both denote the same value.

    2. Check the paths that came from nixpkgs, without Nix and without rebuilding
       anything - a plain GET, no trust required:

         awk '!/^#/ {print $1}' closure-sri-${suffix}.tsv | while read -r p; do
           h=$(basename "$p")
           curl -s "https://cache.nixos.org/''${h%%-*}.narinfo" \
             | sed -n 's/^NarHash: //p'
         done

       Compare each value against the matching `narHash` in `closure-${suffix}.json`.
       Expect a two-part result: the upstream packages confirm, and the locally derived
       paths (the NixOS system itself, generated /etc files, systemd units) exist in no
       binary cache, so nothing can confirm them - only a rebuild is authoritative there.

    3. Rebuild the local store database, then verify every hash:

         nix-store --load-db < nix-path-registration-${suffix}.txt

    4. Check the integrity of the manifest itself:

         sha256sum -c MANIFEST-${suffix}.sha256

    `total-nar-size-${suffix}.txt` gives the total weight of the closure in bytes.
  '';
in
pkgs.runCommand "easy-nix-closure-manifest-${flavour}"
  {
    # Required for `$NIX_ATTRS_JSON_FILE` to exist.
    __structuredAttrs = true;
    # `toplevel` must be a system - pass `config.system.build.toplevel`, never an image
    # whatever this file's name suggests: an image's closure stops at the image file itself,
    # because the squashfs inside is compressed and reference scanning cannot see the store
    # paths within it. A live medium therefore has no such toplevel at all (its layout comes
    # from the image module, so Nix reports a missing root filesystem), and the manifest
    # published with a release describes the system an install produces.
    exportReferencesGraph.easyNix = [ toplevel ];
    nativeBuildInputs = [
      pkgs.jq
      pkgs.coreutils
      pkgs.nix
    ];
    preferLocalBuild = true;
  }
  ''
    mkdir -p $out
    attrs="$NIX_ATTRS_JSON_FILE"

    # `-S` sorts the keys and the filter sorts entries by path, so two builds of the same
    # system produce the same bytes.
    jq -S -f ${jsonFilter} < "$attrs" > $out/closure-${suffix}.json

    # Bare path list, for one-liner comparisons.
    jq -r -f ${pathsFilter} < "$attrs" | sort > $out/store-paths-${suffix}.txt

    # SRI form, directly comparable with a narinfo. `nix hash convert` is a pure
    # computation, so it does not touch the store database and passes the sandbox.
    {
      printf '# path\tnarHash (SRI)\tnarSize\n'
      paste \
        <(jq -r -f ${pathsFilter} < "$attrs") \
        <(jq -r '.easyNix[].narHash' < "$attrs" \
          | xargs nix --extra-experimental-features nix-command \
                  hash convert --from nix32 --to sri) \
        <(jq -r '.easyNix[].narSize' < "$attrs")
    } > $out/closure-sri-${suffix}.tsv

    # `nix-store --load-db` format, so a third party can rebuild the database and verify
    # every hash locally.
    jq -r -f ${registrationFilter} < "$attrs" | head -n -1 \
      > $out/nix-path-registration-${suffix}.txt

    jq -f ${sizeFilter} < "$attrs" > $out/total-nar-size-${suffix}.txt

    cp ${readme} $out/README-${suffix}.txt

    # Fingerprint of the manifest itself. Bare file names, computed from inside $out: a
    # reader runs `sha256sum -c` in their download directory, where `$out/...` does not
    # exist, so store paths here would make the command in the README fail for everyone.
    (cd $out && sha256sum closure-${suffix}.json store-paths-${suffix}.txt \
      closure-sri-${suffix}.tsv) > $out/MANIFEST-${suffix}.sha256

    echo "flavour : ${flavour}"
    echo "system  : ${system}"
    echo "paths   : $(wc -l < $out/store-paths-${suffix}.txt)"
    echo "NAR size: $(cat $out/total-nar-size-${suffix}.txt) bytes"
    echo "manifest:"
    cat $out/MANIFEST-${suffix}.sha256
  ''
