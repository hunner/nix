{
  description = "NixOS configuration for liminal (Framework 16)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    impermanence.url = "github:nix-community/impermanence";
    talon-nix.url = "github:nix-community/talon-nix";
    plover-flake.url = "github:openstenoproject/plover-flake";
    beads-flake.url = "github:steveyegge/beads";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, nixos-hardware, impermanence, talon-nix, plover-flake, beads-flake, ... }:
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
          inherit nixos-hardware impermanence talon-nix plover-flake beads-flake;
        };
        
        modules = [
          # Add unstable overlay
          ({ config, pkgs, ... }: { nixpkgs.overlays = [ overlay-unstable ]; })
          
          # Import configuration
          ./configuration.nix
        ];
      };
    };
}
