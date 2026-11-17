/*
  pi - a terminal coding agent.

  Not in nixpkgs, so it comes from the `llm-agents` catalogue flake, as
  `opencode2` did before it. It replaced opencode2 on size: measured, pi is
  189 MiB of closure and 15 paths, goose-cli - the other candidate - 379 MiB
  and 12, and opencode2 298 MiB. The three differ by more than their binaries
  because each drags its own runtime.

  Nothing is wrapped here: upstream's wrapper already puts `fd` and `ripgrep` on
  PATH and turns telemetry and the version check off. The module exists for the
  assertion, which turns a catalogue that stopped carrying `pi` into a sentence
  rather than an evaluation error three files away.
*/
{
  pkgs,
  inputs,
  ...
}:
let
  llm = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  environment.systemPackages = [ llm.pi ];

  assertions = [
    {
      assertion = llm ? pi;
      message = "easy-nix: the pinned llm-agents revision no longer provides `pi`; update the attribute in modules/apps/pi.nix.";
    }
  ];
}
