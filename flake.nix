{
  description = "easy-nix - a minimal, self-updating NixOS Wayland desktop";

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

    # `pi` is not in nixpkgs, so it comes from a catalogue flake.
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
      # aarch64 is a different product: an SD-card image per board, not an ISO.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [ inputs.treefmt-nix.flakeModule ];

      flake = {
        inherit (hosts) nixosConfigurations packages evalTargets;
      };

      perSystem =
        {
          config,
          system,
          ...
        }:
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
            # The formatting gate runs the very wrapper `nix fmt` runs, so the two cannot
            # disagree. shfmt is deliberately not a separate git hook: the two shfmt
            # defaults differ (tabs versus two spaces) and the hooks then fight treefmt
            # over the same file, red in CI while `nix fmt` calls the tree clean.
            formatting =
              pkgs.runCommand "treefmt-check"
                {
                  nativeBuildInputs = [ config.treefmt.build.wrapper ];
                }
                ''
                  cp -r ${./.} src
                  chmod -R u+w src
                  rm -rf src/.git
                  cd src
                  # The sandbox has no writable HOME for treefmt's cache.
                  treefmt --no-cache --fail-on-change
                  touch $out
                '';

            # Checks with no formatter equivalent.
            pre-commit-check = inputs.git-hooks.lib.${system}.run {
              src = ./.;
              hooks = {
                shellcheck.enable = true;
                end-of-file-fixer.enable = true;
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
          # `formatter` is deliberately absent: treefmt-nix's flakeModule already points
          # it at the treefmt wrapper, which is what makes `nix fmt` use the right tool
          # per language.
        };
    };
}
