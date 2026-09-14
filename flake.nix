{
  description = "NixOS configurations for zima, cryochamber, liminal, and ruil";

  inputs = {
    nixpkgs-25-11.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-26-05.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs-26-05";
    sops-nix.url = "github:Mic92/sops-nix";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    impermanence.url = "github:nix-community/impermanence";
    talon-nix.url = "github:nix-community/talon-nix";
    openclaw-flake.url = "github:openclaw/nix-openclaw";
    plover-flake.url = "github:openstenoproject/plover-flake";
    # Local-only webcam/mic flight recorder. Points at the working tree until
    # the repo is pushed; switch to
    # "git+ssh://git@git.hunner.dev/hunner/flightrec.git" afterwards.
    #flightrec.url = "git+file:///home/hunner/Documents/git/flightrec";
    #flightrec.inputs.nixpkgs.follows = "nixpkgs-26-05";
    #comfyui-nix.url = "github:utensils/comfyui-nix";
    #beads-flake.url = "github:steveyegge/beads?ref=v0.49.6";
    #beads-flake.inputs.nixpkgs.follows = "nixpkgs-25-11";
    #awww.url = "git+https://codeberg.org/LGFae/awww";
    #niri.url = "github:hunner/niri/hunner/focus-to-workspace";
    #niri.inputs.nixpkgs.follows = "nixpkgs-25-11";
  };

  outputs = {
    self,
    nixpkgs-25-11,
    nixpkgs-26-05,
    nixpkgs-unstable,
    home-manager,
    sops-nix,
    nixos-hardware,
    impermanence,
    talon-nix,
    openclaw-flake,
    plover-flake,
    #flightrec,
    #comfyui-nix,
    #beads-flake,
    #awww,
    #niri,
    ...
  }:
    let
      system = "x86_64-linux";

      overlay-unstable = final: prev: {
        unstable = import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            # Upstream re-published Install_NDI_SDK_v6_Linux.tar.gz with a new hash.
            # Remove once nixpkgs-unstable picks up the change.
            (_final: _prev: {
              ndi-6 = _prev.ndi-6.overrideAttrs (old: {
                src = _prev.fetchurl {
                  url = old.src.url;
                  hash = "sha256-8DFPJFRG3vxIi2POtGiazxqWWu79ray3BXG7IWqMwYM=";
                };
              });
            })
          ];
        };
      };

      overlay-etherpad-fixes = final: prev: {
        unstable = prev.unstable // {
          etherpad-lite = prev.unstable.etherpad-lite.overrideAttrs (old: {
            patches =
              (old.patches or [ ])
              ++ [
                ./pkgs/patches/etherpad-plugin-index-keys.patch
                ./pkgs/patches/etherpad-declarative-plugin-packages.patch
                ./pkgs/patches/etherpad-plugin-package-bootstrap-path.patch
              ];
            postInstall =
              (old.postInstall or "")
              + ''
                # Declaratively include ep_author_hover plugin so Etherpad can load it
                # without runtime writes to the Nix store.
                mkdir -p $out/lib/etherpad-lite/src/plugin_packages/ep_author_hover
                tar -xzf ${
                  prev.fetchurl {
                    url = "https://registry.npmjs.org/ep_author_hover/-/ep_author_hover-1.0.12.tgz";
                    hash = "sha256-6/gJTB2GTep/n2ShrNqjzbIW121PYmyTDo/i8LpxjYA=";
                  }
                } \
                  --strip-components=1 \
                  -C $out/lib/etherpad-lite/src/plugin_packages/ep_author_hover \
                  package

                # Declaratively include ep_images_extended plugin so Etherpad can load it
                # without runtime writes to the Nix store.
                mkdir -p $out/lib/etherpad-lite/src/plugin_packages/ep_images_extended
                tar -xzf ${
                  prev.fetchurl {
                    url = "https://registry.npmjs.org/ep_images_extended/-/ep_images_extended-1.1.2.tgz";
                    hash = "sha256-0RPnfQbeqepOPoML2dO7y77yySwQfD04anQdEKwyHNg=";
                  }
                } \
                  --strip-components=1 \
                  -C $out/lib/etherpad-lite/src/plugin_packages/ep_images_extended \
                  package

                # ep_images_extended directly requires mime-db at startup.
                mkdir -p $out/lib/etherpad-lite/src/node_modules/mime-db
                tar -xzf ${
                  prev.fetchurl {
                    url = "https://registry.npmjs.org/mime-db/-/mime-db-1.49.0.tgz";
                    hash = "sha256-tzFKqRPRjkcLki8Kv8HOvmebNq/5hyaGBR7oye+CqZk=";
                  }
                } \
                  --strip-components=1 \
                  -C $out/lib/etherpad-lite/src/node_modules/mime-db \
                  package
              '';
          });
        };
      };

      overlay-local = final: prev: {
        #lean-ctx = prev.callPackage ./pkgs/lean-ctx/package.nix { };
        cliairplay = prev.callPackage ./pkgs/cliairplay/package.nix { };
        codex = prev.callPackage ./pkgs/codex/package.nix { };
        flow = prev.callPackage ./pkgs/flow/package.nix { };
        opencode = prev.callPackage ./pkgs/opencode/package.nix { };
        #pi-coding-agent = prev.callPackage ./pkgs/pi-coding-agent/package.nix { };
        #xai-grok = prev.callPackage ./pkgs/xai-grok/package.nix { };
        #beads =
        #  let
        #    bdBase =
        #      (
        #        final.callPackage "${beads-flake}/default.nix" {
        #          pkgs = final;
        #          self = beads-flake;
        #        }
        #      ).overrideAttrs
        #        (old: {
        #          vendorHash = "sha256-RyOxrW0C+2E+ULhGeF2RbUhaUFt58sux7neHPei5QJI=";
        #          env = (old.env or { }) // {
        #            # Upstream pulls an ICU-backed regex dep; keep Nix build pure-Go.
        #            CGO_ENABLED = "0";
        #          };
        #          postPatch =
        #            (old.postPatch or "")
        #            + ''
        #              # Upstream source currently references a removed internal package.
        #              rm -f cmd/bd/integration_test_stubs_test.go
        #              rm -rf examples/monitor-webui
        #            '';
        #        });
        #  in
        #  final.stdenv.mkDerivation {
        #    pname = "beads";
        #    version = bdBase.version;
        #    phases = [ "installPhase" ];
        #    installPhase = ''
        #      mkdir -p $out/bin
        #      cp ${bdBase}/bin/bd $out/bin/bd

        #      ln -s bd $out/bin/beads

        #      mkdir -p $out/share/fish/vendor_completions.d
        #      mkdir -p $out/share/bash-completion/completions
        #      mkdir -p $out/share/zsh/site-functions

        #      $out/bin/bd completion fish > $out/share/fish/vendor_completions.d/bd.fish
        #      $out/bin/bd completion bash > $out/share/bash-completion/completions/bd
        #      $out/bin/bd completion zsh > $out/share/zsh/site-functions/_bd
        #    '';
        #    meta = bdBase.meta;
        #  };
      };
    in
    {
      nixosConfigurations.zima = nixpkgs-26-05.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit impermanence;
        };
        modules = [
          ({ ... }: { nixpkgs.overlays = [ overlay-unstable ]; })
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

      # Moved 25.11 -> 26.05 on 2026-09-02. 25.11 is EOL, and its forgejo-lts
      # (11.0.15) and forgejo (15.0.3) are both unpatched against
      # CVE-2026-60004; Forgejo 11 LTS ended 2026-07-16 so no fixed 11.x will
      # ever exist. 26.05 ships forgejo-lts 15.0.7, which carries the fix.
      nixosConfigurations.ruil = nixpkgs-26-05.lib.nixosSystem {
        inherit system;
        modules = [
          ({ ... }: { nixpkgs.overlays = [ overlay-unstable overlay-etherpad-fixes overlay-local ]; })
          ./hosts/ruil/configuration.nix
          sops-nix.nixosModules.sops
        ];
      };

      nixosConfigurations.liminal = nixpkgs-26-05.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit
            nixos-hardware
            impermanence
            talon-nix
            plover-flake
            #comfyui-nix
            #beads-flake
            #awww
            #niri
            ;
        };
        modules = [
          ({ ... }: {
            nixpkgs.overlays = [
              overlay-unstable
              overlay-local
              (import ./pkgs/ollama-0329-overlay.nix)
            ];
            # Point <nixpkgs> and flake:nixpkgs at the locked flake input rather than
            # the remote channel registry. Otherwise anything that evals <nixpkgs>
            # (notably nix-direnv, on every cd into a `use nix` dir) re-resolves
            # flake:nixpkgs over the network once tarball-ttl (1h) expires, stalling
            # the shell for seconds. The store path below is already GC-rooted by
            # this system generation, so the lookup is a pure path read.
            nix.nixPath = [ "nixpkgs=${nixpkgs-26-05}" ];
            nix.registry.nixpkgs.flake = nixpkgs-26-05;
          })
          #./hosts/liminal/modules/comfyui
          ./hosts/liminal/modules/airplay
          ./hosts/liminal/modules/yubikey-touch-chime
          ./hosts/liminal/modules/agents-gpg-bridge
          ./hosts/liminal/configuration.nix
          sops-nix.nixosModules.sops
          #flightrec.nixosModules.flightrec
        ];
      };
    };
}
