/*
  OpenCode V2.

  Not in nixpkgs, so it comes from the `llm-agents` catalogue flake. The package is
  wrapped rather than symlinked so the wrapper can carry the environment the tool
  expects; a bare `symlinkJoin` would put the binary on PATH and drop that setting.
*/
{
  pkgs,
  inputs,
  ...
}:
let
  llm = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  opencode = pkgs.symlinkJoin {
    name = "opencode-wrapped";
    paths = [ llm.opencode2 ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/opencode2 --set OPENCODE_ENABLE_EXA 1
    '';
  };
in
{
  environment.systemPackages = [ opencode ];

  # Config is written into the skeleton, not into a live home: a fresh install and a
  # powerwashed machine get it, an existing one keeps whatever the operator changed.
  environment.etc."skel/.config/opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    share = "disabled";
    theme = "system";
  };

  assertions = [
    {
      assertion = llm ? opencode2;
      message = "easy-nix: the pinned llm-agents revision no longer provides `opencode2`; update the attribute in modules/apps/opencode.nix.";
    }
  ];
}
