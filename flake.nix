{
  description = "NixOS configurations for zima, cryochamber, liminal, and ruil";

  inputs = {
    nixpkgs-25-11.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs-25-11";
    sops-nix.url = "github:Mic92/sops-nix";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    impermanence.url = "github:nix-community/impermanence";
    talon-nix.url = "github:nix-community/talon-nix";
    openclaw-flake.url = "github:openclaw/nix-openclaw";
    plover-flake.url = "github:openstenoproject/plover-flake";
    beads-flake.url = "github:steveyegge/beads?ref=v0.49.6";
    beads-flake.inputs.nixpkgs.follows = "nixpkgs-25-11";
    awww.url = "git+https://codeberg.org/LGFae/awww";
    niri.url = "github:hunner/niri/hunner/focus-to-workspace";
    #niri.inputs.nixpkgs.follows = "nixpkgs-25-11";
  };

  outputs = {
    self,
    nixpkgs-25-11,
    nixpkgs-unstable,
    home-manager,
    sops-nix,
    nixos-hardware,
    impermanence,
    talon-nix,
    openclaw-flake,
    plover-flake,
    beads-flake,
    awww,
    niri,
    ...
  }:
    let
      system = "x86_64-linux";

      overlay-unstable = final: prev: {
        unstable = import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      };

      overlay-etherpad-fixes = final: prev: {
        unstable = prev.unstable // {
          etherpad-lite = prev.unstable.etherpad-lite.overrideAttrs (old: {
            patches =
              (old.patches or [ ])
              ++ [
                ./pkgs/patches/etherpad-plugin-index-keys.patch
                ./pkgs/patches/etherpad-declarative-plugin-packages.patch
                ./pkgs/patches/etherpad-plugin-package-bootstrap-path.patch
              ];
            postInstall =
              (old.postInstall or "")
              + ''
                # Declaratively include ep_author_hover plugin so Etherpad can load it
                # without runtime writes to the Nix store.
                mkdir -p $out/lib/etherpad-lite/src/plugin_packages/ep_author_hover
                tar -xzf ${
                  prev.fetchurl {
                    url = "https://registry.npmjs.org/ep_author_hover/-/ep_author_hover-1.0.12.tgz";
                    hash = "sha256-6/gJTB2GTep/n2ShrNqjzbIW121PYmyTDo/i8LpxjYA=";
                  }
                } \
                  --strip-components=1 \
                  -C $out/lib/etherpad-lite/src/plugin_packages/ep_author_hover \
                  package

                # Declaratively include ep_images_extended plugin so Etherpad can load it
                # without runtime writes to the Nix store.
                mkdir -p $out/lib/etherpad-lite/src/plugin_packages/ep_images_extended
                tar -xzf ${
                  prev.fetchurl {
                    url = "https://registry.npmjs.org/ep_images_extended/-/ep_images_extended-1.1.2.tgz";
                    hash = "sha256-0RPnfQbeqepOPoML2dO7y77yySwQfD04anQdEKwyHNg=";
                  }
                } \
                  --strip-components=1 \
                  -C $out/lib/etherpad-lite/src/plugin_packages/ep_images_extended \
                  package

                # ep_images_extended directly requires mime-db at startup.
                mkdir -p $out/lib/etherpad-lite/src/node_modules/mime-db
                tar -xzf ${
                  prev.fetchurl {
                    url = "https://registry.npmjs.org/mime-db/-/mime-db-1.49.0.tgz";
                    hash = "sha256-tzFKqRPRjkcLki8Kv8HOvmebNq/5hyaGBR7oye+CqZk=";
                  }
                } \
                  --strip-components=1 \
                  -C $out/lib/etherpad-lite/src/node_modules/mime-db \
                  package
              '';
          });
        };
      };

      overlay-local = final: prev: {
        codex = prev.callPackage ./pkgs/codex/package.nix { };
        beads =
          let
            bdBase =
              (
                final.callPackage "${beads-flake}/default.nix" {
                  pkgs = final;
                  self = beads-flake;
                }
              ).overrideAttrs
                (old: {
                  vendorHash = "sha256-RyOxrW0C+2E+ULhGeF2RbUhaUFt58sux7neHPei5QJI=";
                  env = (old.env or { }) // {
                    # Upstream pulls an ICU-backed regex dep; keep Nix build pure-Go.
                    CGO_ENABLED = "0";
                  };
                  postPatch =
                    (old.postPatch or "")
                    + ''
                      # Upstream source currently references a removed internal package.
                      rm -f cmd/bd/integration_test_stubs_test.go
                      rm -rf examples/monitor-webui
                    '';
                });
          in
          final.stdenv.mkDerivation {
            pname = "beads";
            version = bdBase.version;
            phases = [ "installPhase" ];
            installPhase = ''
              mkdir -p $out/bin
              cp ${bdBase}/bin/bd $out/bin/bd

              ln -s bd $out/bin/beads

              mkdir -p $out/share/fish/vendor_completions.d
              mkdir -p $out/share/bash-completion/completions
              mkdir -p $out/share/zsh/site-functions

              $out/bin/bd completion fish > $out/share/fish/vendor_completions.d/bd.fish
              $out/bin/bd completion bash > $out/share/bash-completion/completions/bd
              $out/bin/bd completion zsh > $out/share/zsh/site-functions/_bd
            '';
            meta = bdBase.meta;
          };
      };
    in
    {
      nixosConfigurations.zima = nixpkgs-25-11.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit impermanence;
        };
        modules = [
          ./hosts/zima/configuration.nix
          sops-nix.nixosModules.sops
        ];
      };

      nixosConfigurations.cryochamber = nixpkgs-25-11.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit impermanence;
        };
        modules = [
          ./hosts/cryochamber/configuration.nix
          sops-nix.nixosModules.sops
        ];
      };

      nixosConfigurations.ruil = nixpkgs-25-11.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit openclaw-flake;
        };
        modules = [
          ({ ... }: { nixpkgs.overlays = [ overlay-unstable overlay-etherpad-fixes openclaw-flake.overlays.default ]; })
          home-manager.nixosModules.home-manager
          ./hosts/ruil/configuration.nix
          sops-nix.nixosModules.sops
        ];
      };

      nixosConfigurations.liminal = nixpkgs-25-11.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit
            nixos-hardware
            impermanence
            talon-nix
            plover-flake
            beads-flake
            awww
            niri
            ;
        };
        modules = [
          ({ ... }: { nixpkgs.overlays = [ overlay-unstable overlay-local ]; })
          ./hosts/liminal/configuration.nix
          sops-nix.nixosModules.sops
        ];
      };
    };
}
