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
    beads-flake.url = "github:steveyegge/beads";
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
                  vendorHash = "sha256-cMvxGJBMUszIbWwBNmWe+ws4m3mfyEZgapxVYNYc5c4=";
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
          ({ ... }: { nixpkgs.overlays = [ openclaw-flake.overlays.default ]; })
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
