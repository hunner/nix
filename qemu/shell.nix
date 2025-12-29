let
  pkgs = import <nixpkgs> { config.allowUnfree = true; };
  #unstable = import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixpkgs-unstable.tar.gz") { 
  #  config.allowUnfree = true;
  #};
in pkgs.mkShell {
  packages = with pkgs; [
    qemu
  ];
}
