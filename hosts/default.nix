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
      home,
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
      modules = [
        ../modules/base.nix
        inputs.home-manager.nixosModules.home-manager
        {
          # `home-manager` was an input nothing imported: every `hosts/<host>/home.nix`
          # and all of `modules/desktop/niri.nix` were unreachable, and the desktop on the
          # image was whatever niri generates for itself on first start - no keybindings
          # of ours, no keyboard layout, no mako, no swayidle. Measured, not assumed: the
          # session came up on a straight `niri-session`, wrote its own default config,
          # and the marker in nix/session-report.sh (a user unit in niri.nix) never
          # existed to run.
          #
          # `useGlobalPkgs` so that the user configuration is built with the same nixpkgs
          # as the system - two evaluations of nixpkgs in one image is how a closure
          # doubles. `useUserPackages` so that its packages land in the user's profile
          # rather than in the system one: the units and the config files are then the
          # user's, which is what makes `systemctl --user` and a per-session restart mean
          # anything.
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.${user} = import home;
          };
        }
      ]
      ++ modules;
    };

  # Two instruments the release page publishes instead of a promise:
  #
  #   - a closure manifest, listing every store path a system is made of, with its hash
  #     in both encodings, so a reader can check what they installed against their own
  #     store or against cache.nixos.org, without trusting whoever ran the build;
  #   - a size budget, which turns "the image grew" into a red check on the commit that
  #     caused it, instead of a surprise at the last step of a release job.
  #
  # Both are keyed by flavour and system, and only a host that can produce them has
  # them: a live medium has no evaluable toplevel to describe, and an image-rooted
  # manifest would describe nothing.
  pkgsFor = system: inputs.nixpkgs.legacyPackages.${system};

  mkClosureManifest =
    system: flavour: toplevel:
    (pkgsFor system).callPackage ../nix/closure-manifest.nix { inherit toplevel flavour; };

  mkSizeBudget =
    system: flavour: image: budgetMiB:
    (pkgsFor system).callPackage ../nix/size-budget.nix { inherit image flavour budgetMiB; };

  nixosConfigurations = {
    # The appliance as installed on a disk.
    easy-nix = mkHost {
      hostName = "easy-nix";
      modules = [ ./easy-nix ];
      home = ./easy-nix/home.nix;
    };

    # The bootable installer: the same system, plus the install tool and a marker
    # service. Its `system.build.images.iso` is what gets released.
    easy-nix-live = mkHost {
      hostName = "easy-nix-live";
      modules = [ ./easy-nix-live ];
      home = ./easy-nix-live/home.nix;
    };

    # Deliberately light: no browsers, no office suite, no Steam. Exists so a boot
    # test can run on a machine that cannot build (or boot) the full image. It proves
    # the live machinery and the Wayland session start, nothing about the applications.
    easy-nix-live-test = mkHost {
      hostName = "easy-nix-live-test";
      modules = [ ./easy-nix-live-test ];
      home = ./easy-nix-live-test/home.nix;
    };

    # Light for the same reason, plus the installer and an unattended install onto the
    # disk the install test attaches. This is the only host that partitions anything.
    easy-nix-live-install-test = mkHost {
      hostName = "easy-nix-live-install-test";
      modules = [ ./easy-nix-live-install-test ];
      home = ./easy-nix-live-install-test/home.nix;
    };

    # ARM: an SD-card image per board, reduced application set. See README.
    easy-nix-arm = mkHost {
      hostName = "easy-nix-arm";
      system = "aarch64-linux";
      modules = [ ./easy-nix-arm ];
      home = ./easy-nix-arm/home.nix;
    };
  };

  # Nothing here is a build of a whole system, so it is cheap to evaluate.
  packages = {
    x86_64-linux = {
      iso = nixosConfigurations.easy-nix-live.config.system.build.images.iso;
      iso-test = nixosConfigurations.easy-nix-live-test.config.system.build.images.iso;
      iso-install-test = nixosConfigurations.easy-nix-live-install-test.config.system.build.images.iso;
      vm = nixosConfigurations.easy-nix.config.system.build.vm;

      # The closure of the system an install produces. This is the claim the release page
      # can actually support, and it is deliberately NOT rooted at the medium: an image's
      # own closure stops at the ISO file, because the squashfs inside is compressed and
      # reference scanning cannot see the store paths within it. Measured, not guessed -
      # the first CI run that built this reported `paths: 1`, the ISO and nothing else.
      closure-manifest-appliance =
        mkClosureManifest "x86_64-linux" "appliance"
          nixosConfigurations.easy-nix.config.system.build.toplevel;

      # Measured ceilings, in MiB, with the reason for each number in docs/budget.md.
      # The installer one matters most: GitHub refuses a release asset above 2 GiB and
      # this image is twice that, which is why it ships in parts.
      size-budget-installer =
        mkSizeBudget "x86_64-linux" "installer"
          nixosConfigurations.easy-nix-live.config.system.build.images.iso
          4100;
      size-budget-test =
        mkSizeBudget "x86_64-linux" "test"
          nixosConfigurations.easy-nix-live-test.config.system.build.images.iso
          2048;
    };
    aarch64-linux = {
      sd-card = nixosConfigurations.easy-nix-arm.config.system.build.images.sd-card;
    };
  };
in
{
  inherit nixosConfigurations packages;

  # What it means to "evaluate this host", one honest answer per host.
  #
  # A host that only exists to produce an image is evaluated through its image variant:
  # its plain top-level has no filesystem layout *on purpose*, because the image module
  # declares one (which is also why `nixos-rebuild switch` on `easy-nix-live` is
  # meaningless and fails with an assertion about a missing root filesystem). Evaluating
  # `system.build.toplevel` there proves nothing and fails loudly for the wrong reason.
  evalTargets = {
    easy-nix = nixosConfigurations.easy-nix.config.system.build.toplevel.drvPath;
    easy-nix-live = nixosConfigurations.easy-nix-live.config.system.build.images.iso.drvPath;
    easy-nix-live-test = nixosConfigurations.easy-nix-live-test.config.system.build.images.iso.drvPath;
    easy-nix-live-install-test =
      nixosConfigurations.easy-nix-live-install-test.config.system.build.images.iso.drvPath;
    easy-nix-arm = nixosConfigurations.easy-nix-arm.config.system.build.images.sd-card.drvPath;
  };

  bootTests = {
    x86_64-linux = import ./boot-tests.nix {
      inherit inputs;
      iso = packages.x86_64-linux.iso-test;
      isoRelease = packages.x86_64-linux.iso;
      isoInstallTest = packages.x86_64-linux.iso-install-test;
    };
  };
}
