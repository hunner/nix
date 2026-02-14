{
  description = "NixOS configurations for zima, cryochamber, liminal, and ruil";

  inputs = {
    nixpkgs-25-11.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    impermanence.url = "github:nix-community/impermanence";
    talon-nix.url = "github:nix-community/talon-nix";
    plover-flake.url = "github:openstenoproject/plover-flake";
    beads-flake.url = "github:steveyegge/beads";
    awww.url = "git+https://codeberg.org/LGFae/awww";
    niri.url = "github:hunner/niri/hunner/focus-to-workspace";
    #niri.inputs.nixpkgs.follows = "nixpkgs-25-11";
  };

  outputs = {
    self,
    nixpkgs-25-11,
    nixpkgs-unstable,
    sops-nix,
    nixos-hardware,
    impermanence,
    talon-nix,
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
        modules = [
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
