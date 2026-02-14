# Deploy config to a host (builds remotely, activates remotely)
deploy host target:
  nixos-rebuild switch \
    --flake .#{{host}} \
    --target-host {{target}} \
    --build-host {{target}}

# Deploy config to a host
deploy-sudo host:
  sudo nixos-rebuild switch \
    --flake .#{{host}}

# Shortcut: deploy ruil (remote)
deploy-ruil:
  just deploy ruil root@ruil.hunnur.com

# Shortcut: deploy liminal (local)
deploy-liminal:
  just deploy-sudo liminal

# Update flake lock file
update:
  nix flake update
