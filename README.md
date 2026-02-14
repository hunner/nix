# NixOS Configurations

Flake-based NixOS configurations for zima, cryochamber, liminal, and ruil.

## Hosts

| Host | Description |
|------|-------------|
| zima | Local server (ZFS, impermanence) |
| cryochamber | zfs.rent server (impermanence) |
| liminal | Workstation (hardware-specific overlays) |
| ruil | Digital Ocean droplet (ams3) |

## Deploying

After changing a host's config, deploy with:

```sh
# Build and activate on the remote host
just deploy ruil root@ruil.hunnur.com

# Or build and activate locally via sudo
just deploy-sudo ruil
```

There's also a shortcut:

```sh
just deploy-ruil
```

For local hosts, just run:

```sh
sudo nixos-rebuild switch --flake .#zima
```

## Secrets (sops-nix)

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix) using age keys. Each host's secrets live in `hosts/<name>/secrets/config.yaml`.

Host age keys are derived from SSH host keys:

```sh
ssh <host> 'cat /etc/ssh/ssh_host_ed25519_key.pub' | nix run 'nixpkgs#ssh-to-age'
```

To edit a host's secrets:

```sh
sops edit hosts/<name>/secrets/config.yaml
```

## Available Commands

| Command | Description |
|---------|-------------|
| `just deploy <host> <target>` | Build remotely and activate |
| `just deploy-sudo <host>` | Build locally and activate |
| `just deploy-ruil` | Deploy ruil (shortcut) |
| `just deploy-liminal` | Deploy liminal (shortcut) |
| `just update` | Update flake lock file |
