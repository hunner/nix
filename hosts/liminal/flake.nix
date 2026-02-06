{
  description = "NixOS configuration for liminal (Framework 16)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixos-hardware.url = "github:NixOS/nixos-hardware";
    impermanence.url = "github:nix-community/impermanence";
    talon-nix.url = "github:nix-community/talon-nix";
    plover-flake.url = "github:openstenoproject/plover-flake";
    beads-flake.url = "github:steveyegge/beads";
    awww.url = "git+https://codeberg.org/LGFae/awww";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    niri.url = "github:hunner/niri/hunner/focus-to-workspace";
    niri.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-unstable,
    nixos-hardware,
    impermanence,
    talon-nix,
    plover-flake,
    beads-flake,
    awww,
    sops-nix,
    niri,
    ...
  }:
    let
      system = "x86_64-linux";

      # Create unstable overlay
      overlay-unstable = final: prev: {
        unstable = import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      };
    in
    {
      nixosConfigurations.liminal = nixpkgs.lib.nixosSystem {
        inherit system;

        specialArgs = {
          inherit nixos-hardware impermanence talon-nix plover-flake beads-flake awww niri;
        };

        modules = [
          # Add unstable overlay
          ({ config, pkgs, ... }: { nixpkgs.overlays = [ overlay-unstable ]; })

          # Add sops
          sops-nix.nixosModules.sops

          # Import configuration
          ./configuration.nix
        ];
      };
    };
}
