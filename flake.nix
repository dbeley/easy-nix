{
  description = "easy-nix — a minimal, self-updating NixOS Wayland desktop";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";

    flake-parts.url = "github:hercules-ci/flake-parts";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # OpenCode V2 and friends. Not in nixpkgs, so it comes from a catalog flake.
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ self, flake-parts, ... }:
    let
      hosts = import ./hosts { inherit self inputs; };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      # aarch64 is a supported target but a different product: see README (no Steam,
      # SD-card image per board instead of an ISO).
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [ inputs.treefmt-nix.flakeModule ];

      flake = {
        inherit (hosts) nixosConfigurations;
      };

      flake.evalTargets = hosts.evalTargets;

      perSystem =
        { system, ... }:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
          bootTests = hosts.bootTests.${system} or { };
        in
        {
          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              nixfmt.enable = true;
              statix.enable = true;
              deadnix.enable = true;
              shellcheck.enable = true;
              shfmt.enable = true;
            };
          };

          checks = {
            pre-commit-check = inputs.git-hooks.lib.${system}.run {
              src = ./.;
              hooks = {
                nixfmt.enable = true;
                statix.enable = true;
                deadnix.enable = true;
                end-of-file-fixer.enable = true;
                shellcheck.enable = true;
                shfmt.enable = true;
                trim-trailing-whitespace.enable = true;
              };
            };
          }
          // bootTests;

          devShells.default =
            let
              pre-commit = self.checks.${system}.pre-commit-check;
            in
            pkgs.mkShell {
              inherit (pre-commit) shellHook;
              packages =
                pre-commit.enabledPackages
                ++ (with pkgs; [
                  nixos-rebuild
                  qemu_kvm
                ]);
            };
          # `formatter` is deliberately not set here: treefmt-nix's flakeModule
          # already points it at the treefmt wrapper, which is what makes `nix fmt`
          # format Nix, shell and markdown with the right tool each.
        };

      flake.packages = hosts.packages;
    };
}
