{
  inputs = {
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    sops-nix,
  }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.cryochamber = nixpkgs.lib.nixosSystem {
        modules = [
          ./configuration.nix
          sops-nix.nixosModules.sops
        ];
      };
    };
}
