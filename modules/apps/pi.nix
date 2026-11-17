/*
  pi - a terminal coding agent, from the `llm-agents` catalogue flake because it is not in
  nixpkgs.

  Nothing is wrapped here: upstream's wrapper already puts `fd` and `ripgrep` on PATH and
  turns telemetry and the version check off. The module exists for the assertion, which
  turns a catalogue that stopped carrying `pi` into a sentence rather than an evaluation
  error three files away.
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
