/*
  Host definitions.

  Every host is built through `mkHost`, which wires up:
    - the shared system base (`modules/base.nix`)
    - home-manager, with `hosts/<host>/home.nix` as the user configuration
    - the specialArgs downstream modules expect (`user`, `hostName`, `inputs`, `flakeSelf`)

  `flakeSelf` is the flake itself, so the live image can embed its own source and
  `nixos-install` can run from the medium without network access to the repository.
*/
{ self, inputs }:
let
  inherit (inputs.nixpkgs) lib;

  user = "easy";

  # Bumped deliberately, never automatically: it is the escape hatch that keeps a
  # stateful option from changing meaning under an existing installation.
  stateVersion = "26.05";

  mkHost =
    {
      hostName,
      system ? "x86_64-linux",
      modules,
    }:
    lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit
          inputs
          user
          hostName
          stateVersion
          ;
        flakeSelf = self;
      };
      modules = [ ../modules/base.nix ] ++ modules;
    };

  nixosConfigurations = {
    # The appliance as installed on a disk.
    easy-nix = mkHost {
      hostName = "easy-nix";
      modules = [ ./easy-nix ];
    };

    # The bootable installer: the same system, plus the install tool and a marker
    # service. Its `system.build.images.iso` is what gets released.
    easy-nix-live = mkHost {
      hostName = "easy-nix-live";
      modules = [ ./easy-nix-live ];
    };

    # Deliberately light: no browsers, no office suite, no Steam. Exists so a boot
    # test can run on a machine that cannot build (or boot) the full image. It proves
    # the live machinery and the Wayland session start, nothing about the applications.
    easy-nix-live-test = mkHost {
      hostName = "easy-nix-live-test";
      modules = [ ./easy-nix-live-test ];
    };

    # ARM: an SD-card image per board, reduced application set. See README.
    easy-nix-arm = mkHost {
      hostName = "easy-nix-arm";
      system = "aarch64-linux";
      modules = [ ./easy-nix-arm ];
    };
  };

  # Nothing here is a build of a whole system, so it is cheap to evaluate.
  packages = {
    x86_64-linux = {
      iso = nixosConfigurations.easy-nix-live.config.system.build.images.iso;
      iso-test = nixosConfigurations.easy-nix-live-test.config.system.build.images.iso;
      vm = nixosConfigurations.easy-nix.config.system.build.vm;
    };
    aarch64-linux = {
      sd-card = nixosConfigurations.easy-nix-arm.config.system.build.images.sd-card;
    };
  };
in
{
  inherit nixosConfigurations packages;

  bootTests = {
    x86_64-linux = import ./boot-tests.nix {
      inherit inputs;
      iso = packages.x86_64-linux.iso-test;
      isoRelease = packages.x86_64-linux.iso;
    };
  };
}
