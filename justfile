# Deploy config to a host (builds remotely, activates remotely)
build-deploy-remote host target:
  nixos-rebuild switch \
    --flake .#{{host}} \
    --target-host {{target}} \
    --build-host {{target}}

# Deploy config to a host (builds locally, activates remotely)
deploy-remote host target:
  nixos-rebuild switch \
    --flake .#{{host}} \
    --target-host {{target}}

# Deploy config to a host (builds locally, activates locally)
deploy-sudo host:
  sudo nixos-rebuild switch \
    --flake .#{{host}}

# Shortcut helper: deploy locally when host matches this machine, otherwise deploy remotely.
deploy-auto host target:
  if [ "$(hostname -s)" = "{{host}}" ]; then just deploy-sudo {{host}}; else just deploy-remote {{host}} {{target}}; fi

# Shortcut: deploy ruil
deploy-ruil:
  just deploy-auto ruil root@ruil.hunnur.com

# Shortcut: deploy liminal
deploy-liminal:
  just deploy-auto liminal root@liminal

# Shortcut: deploy zima
deploy-zima:
  just deploy-auto zima root@zima

update-package package version="":
  if [ -n "{{version}}" ]; then scripts/update-local-package {{package}} --version {{version}}; else scripts/update-local-package {{package}}; fi

# Update flake lock file
update:
  nix flake update
