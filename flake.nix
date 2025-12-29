{
  description = "NixOS configurations for zima, cryochamber, and liminal";

  inputs = {
    nixpkgs-23-11.url = "github:NixOS/nixpkgs/nixos-23.11";
    nixpkgs-25-05.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-25-11.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    impermanence.url = "github:nix-community/impermanence";
    talon-nix.url = "github:nix-community/talon-nix";
    plover-flake.url = "github:openstenoproject/plover-flake";
    beads-flake.url = "github:steveyegge/beads";
  };

  outputs = { self, nixpkgs-23-11, nixpkgs-25-05, nixpkgs-25-11, nixpkgs-unstable, sops-nix, nixos-hardware, impermanence, talon-nix, plover-flake, beads-flake, ... }:
    let
      system = "x86_64-linux";
      overlay-unstable = final: prev: {
        unstable = import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      };
    in
    {
      nixosConfigurations.zima = nixpkgs-23-11.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit impermanence;
        };
        modules = [
          ./hosts/zima/configuration.nix
          sops-nix.nixosModules.sops
        ];
      };

      nixosConfigurations.cryochamber = nixpkgs-25-05.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit impermanence;
        };
        modules = [
          ./hosts/cryochamber/configuration.nix
          sops-nix.nixosModules.sops
        ];
      };

      nixosConfigurations.liminal = nixpkgs-25-11.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit nixos-hardware impermanence talon-nix plover-flake beads-flake;
        };
        modules = [
          ({ ... }: { nixpkgs.overlays = [ overlay-unstable ]; })
          ./hosts/liminal/configuration.nix
        ];
      };
    };
}
