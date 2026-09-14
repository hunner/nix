# Config for framework16
{
  config,
  pkgs,
  lib,
  nixos-hardware,
  impermanence,
  talon-nix,
  plover-flake,
  #codex,
  #beads-flake,
  #awww,
  #niri,
  ... }:
  {
  nix.settings = {
    download-buffer-size = 524288000; # 500 MiB
  };
  imports =
    [
      nixos-hardware.nixosModules.framework-16-7040-amd
      ./hardware-configuration.nix
      impermanence.nixosModules.impermanence
      talon-nix.nixosModules.talon
    ];

  boot = {
    loader.systemd-boot.enable = true;
    loader.systemd-boot.configurationLimit = 20;
    loader.efi.canTouchEfiVariables = true;
    #initrd.luks.devices."cryptroot".device = "/dev/disk/by-partlabel/disk-nvme0n1-cryptroot";
    initrd.luks.devices."cryptswap".device = "/dev/disk/by-partlabel/disk-nvme0n1-swap";

    resumeDevice = "/dev/mapper/cryptswap";
    kernelParams = [
      # Keep the console alive across suspend/hibernate so the kernel messages
      # from a failing snapshot reach the journal (and pstore) instead of being
      # swallowed once the console is suspended.
      "no_console_suspend"
    ];
    extraModprobeConfig = ''
      options amdgpu cwsr_enable=0 # For ROCm to not crash
    '';
    # Crash forensics: this kernel has CONFIG_EFI_VARS_PSTORE=y (built in, and
    # CONFIG_EFI_VARS_PSTORE_DEFAULT_DISABLE is unset), so efi-pstore is already
    # active and /sys/fs/pstore is mounted. systemd-pstore.service is enabled by
    # NixOS and copies whatever survived into /var/lib/systemd/pstore, which is
    # a real btrfs subvolume here. Nothing to enable; ramoops is unnecessary.
    # There is no kdump crash kernel loaded, so crash_kexec_post_notifiers would
    # be a no-op and is deliberately left off.
    tmp.cleanOnBoot = true; # /tmp is persisted now (see environment.persistence)
  };
  swapDevices = [ {
    device = "/dev/mapper/cryptswap";
  } ];

  # Cap the hibernate image at 16 GiB. This is a soft target: memory that does
  # not fit in the image is swapped out first, so nothing is lost. At snapshot
  # time RAM holds the image pages plus a copy of each (~2x the target), and
  # amdgpu must then still allocate GTT pages to evict VRAM under GFP_NOIO (no
  # reclaim possible). A 50 GiB target starved that eviction (ENOMEM) and the
  # failed hibernate let the battery drain to hard power-off (2026-08-13).
  systemd.tmpfiles.rules = [
    "w /sys/power/image_size - - - - 17179869184"
  ];

  # The journal lives on /var/log (a real btrfs subvolume), but the default 4 GB
  # cap only held ~11 days, so every hibernate failure before 2026-08-26 had
  # already rotated away before it could be looked at.
  services.journald.extraConfig = ''
    SystemMaxUse=8G
  '';

  # A failed hibernate used to leave the machine awake with a blank screen until
  # the battery hit hard power-off, which writes nothing to the journal. Power
  # off cleanly instead: the session is lost either way, but the filesystems are
  # unmounted and the failure is on record.
  systemd.services.hibernate-fallback-poweroff = {
    description = "Power off after a failed hibernate";
    serviceConfig = {
      Type = "oneshot";
      # --no-block: this unit is stopped by the shutdown transaction it queues.
      ExecStart = "${config.systemd.package}/bin/systemctl --no-block poweroff";
    };
  };

  # Snapshotting needs ~32 GiB of RAM free; on 2026-08-26 only ~24.8 GiB was,
  # and the kernel returned "Error -12 creating image". Free the two biggest
  # pinned consumers before the snapshot and bring them back on resume.
  # llama-swap keeps a multi-GiB model resident (RAM plus amdgpu GTT), and
  # docker holds the k3s/supabase containers and their page cache.
  #
  # Both Exec lines are "-" prefixed and the restart is --no-block, so a service
  # that refuses to stop (or to come back) never blocks or fails the hibernate.
  # Note that suspend-then-hibernate does *not* run this unit for its hibernate
  # phase -- systemd-sleep hibernates in-process -- so that path only gets the
  # poweroff fallback. If it turns out to be the common failure, move the
  # shrink into /etc/systemd/system-sleep, which is called per phase.
  systemd.services.systemd-hibernate = let
    systemctl = "${config.systemd.package}/bin/systemctl";
    # docker.socket too, or socket activation restarts dockerd immediately.
    heavy = "llama-swap.service docker.service docker.socket";
  in {
    overrideStrategy = "asDropin"; # upstream unit; only drop in on top of it
    unitConfig.OnFailure = "hibernate-fallback-poweroff.service";
    serviceConfig = {
      ExecStartPre = [
        "-${systemctl} stop ${heavy}"
        "-${pkgs.runtimeShell} -c 'sync; echo 3 > /proc/sys/vm/drop_caches'"
      ];
      ExecStopPost = [
        "-${systemctl} --no-block start ${heavy}"
      ];
      # The upstream unit inherits the 90s default, which now also has to cover
      # stopping docker. Generous, but still finite: a hibernate that hangs
      # should time out into the poweroff above rather than sit on the battery.
      TimeoutStartSec = "10min";
    };
  };
  # suspend-then-hibernate (the power key) hibernates from its own unit, so it
  # needs the same fallback.
  systemd.services.systemd-suspend-then-hibernate = {
    overrideStrategy = "asDropin";
    unitConfig.OnFailure = "hibernate-fallback-poweroff.service";
  };

  services.fwupd.enable = true;
  hardware.framework.enableKmod = true;

  fileSystems = {
    "/" = {
      device = "none";
      fsType = "tmpfs";
      options = [ "defaults" "size=17G" "mode=755" ];
    };
    "/persist" = {
      neededForBoot = true;
    };
  };

  hardware.amdgpu = {
    opencl.enable = true;
  };
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "amdgpu" ];
  services.nextjs-ollama-llm-ui = {
    enable = true;
    port = 4666;
  };
  services.ollama = {
    enable = false;
    package = pkgs.unstable.ollama-vulkan;
    loadModels = [ ];
    #loadModels = [ "qwen3.5" "gpt-oss" "ornith:9b" "ornith:35b" ];
    environmentVariables = {
      OLLAMA_IGPU_ENABLE = "1";
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KV_CACHE_TYPE = "q8_0";
    };
  };
  services.llama-swap = {
    enable = true;
    port = 11434;
    settings = let
      llamaServer = lib.getExe' pkgs.unstable.llama-cpp-vulkan "llama-server";
    in {
      hooks.on_startup.preload = [ "qwen3.8:27b" ];
      # Benchmarked 2026-08-16 on the 780M iGPU, 250-token decode with MTP:
      # Q4_K_M 6.6 t/s, Q5_K_M 5.4 t/s, IQ4_XS 5.0 t/s (IQ dequant is
      # compute-bound on Vulkan, so the smaller file loses). Without MTP all
      # sit at 3.7-4.3 t/s.
      models."qwen3.8:27b" = {
        cmd = "${llamaServer} --port \${PORT} -m /var/lib/llama-swap/models/Qwen3.8-27B-Uncensored-Q4_K_M.gguf -c 151072 -ngl 999 -fa 1 --jinja --parallel 1 --spec-type draft-mtp --spec-draft-n-max 2 --spec-draft-p-min 0.6 --cache-type-k q8_0 --cache-type-v q8_0 --temp 0.55 --top-p 0.9 --top-k 40 --repeat-penalty 1.1";
      };
      models."qwen3.8:27b-q5" = {
        cmd = "${llamaServer} --port \${PORT} -m /var/lib/llama-swap/models/Qwen3.8-27B-Uncensored-Q5_K_M.gguf -c 131072 -ngl 999 -fa 1 --jinja --parallel 1 --spec-type draft-mtp --spec-draft-n-max 2 --spec-draft-p-min 0.6 --cache-type-k q8_0 --cache-type-v q8_0 --temp 0.55 --top-p 0.9 --top-k 40 --repeat-penalty 1.1";
        aliases = [ "bughunt" ];
      };
      # outsourc-e Unleashed (Heretic abliteration, Unsloth Dynamic v3 quants,
      # MTP tensors kept). The author's 4090 table (X @outsource_, 2026-08-21)
      # has UD-Q3_K_XL at better PPL than UD-Q4 (6.399 vs 6.418) at 13.2 GB vs
      # 16.5 GB, so the Q3 should win on this bandwidth-bound iGPU; Q3_K
      # dequant is cheap on Vulkan, unlike the IQ quants above. p-min 0.75:
      # gating helps bandwidth-starved rigs (M5 MacBook went 7.2->10.5 t/s at
      # p-min 0.8; fast desktop cards prefer no gate). q4_0 KV and samplers
      # are the model-card recommendation. Benchmarked 2026-08-21, 250-token
      # decode at temp 0: UD-Q3_K_XL 7.5 t/s (93% draft acceptance), UD-Q4_K_M
      # 6.0 t/s. Raising n-max needs a rebuild per value (the server clamps
      # per-request overrides to the CLI ceiling); 890M peaked at 2, Strix
      # Halo at 12, and temp-0 acceptance overstates what temp 1.0 will get.
      models."qwen3.8:27b-unleashed" = {
        cmd = "${llamaServer} --port \${PORT} -m /var/lib/llama-swap/models/Qwen3.8-27B-Unleashed-UD-Q3_K_XL.gguf -c 262144 -ngl 999 -fa 1 --jinja --parallel 1 -b 2048 -ub 512 --cache-reuse 256 --spec-type draft-mtp --spec-draft-n-max 2 --spec-draft-p-min 0.75 --cache-type-k q4_0 --cache-type-v q4_0 --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0 --repeat-penalty 1.0";
        aliases = [ "unleashed" ];
      };
      models."qwen3.5:4b" = {
        cmd = "${llamaServer} --port \${PORT} -m /var/lib/llama-swap/models/Qwen_Qwen3.5-4B-Q5_K_L.gguf -c 65536";
        aliases = [ "qwen" ];
      };
      models."qwen3.5:35b" = {
        cmd = "${llamaServer} --port \${PORT} -m /var/lib/llama-swap/models/Qwen_Qwen3.5-35B-A3B-Q5_K_L.gguf -c 65536 --mmap --gpu-layers 35";
        aliases = [ "qwen3.5" ];
      };
    };
  };
  systemd.services.llama-swap = {
    environment = {
      HOME = "/var/lib/llama-swap";
      XDG_CACHE_HOME = "/var/cache/llama-swap";
    };
    serviceConfig = {
      StateDirectory = "llama-swap";
      CacheDirectory = "llama-swap";
    };
  };

  networking.hostId = "3294c9a2"; # Required for ZFS
  networking.hostName = "liminal";
  networking.networkmanager.enable = true;
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.extraHosts =
    ''
      127.0.0.1 keycloak
      127.0.0.1 k3d-cmvm
      172.17.0.1 docker.host.internal
    '';

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/root"
      "/etc/nixos"
      "/etc/ssh"
      "/etc/NetworkManager/system-connections"
      # / is tmpfs, so /tmp was RAM. Nix builds and container scratch space put
      # gigabytes there that the hibernate snapshot then has to carry. Bind it
      # to the btrfs subvolume instead; boot.tmp.cleanOnBoot wipes it each boot,
      # so it keeps /tmp semantics and does not grow on disk.
      { directory = "/tmp"; mode = "1777"; }
    ];
    files = [
      "/etc/machine-id"
      #"/etc/nix/id_rsa" # Needed?
    ];
  };
  # Files are not copied to /persist during install, so need to do so manually
  #rsync -azPH /mnt/root/ /mnt/persist/root
  #rsync -azPH /mnt/etc/nixos/ /mnt/persist/etc/nixos
  #rsync -azPH /mnt/etc/ssh/ /mnt/persist/etc/ssh
  #cp /mnt/etc/machine-id /mnt/persist/etc/machine-id
  security.sudo.extraConfig = ''
    # Don't lecture after reboot
    Defaults lecture = never

    # Let hunner run commands as the agents user without a password.
    hunner ALL=(agents) NOPASSWD: ALL
  '';
  # Add local development CA
  security.pki.certificates = [
    ''
      -----BEGIN CERTIFICATE-----
      MIIDWjCCAkKgAwIBAgIUGRnCFfA+iZqheSfHGXSccBYVFsUwDQYJKoZIhvcNAQEL
      BQAwGzEZMBcGA1UEAwwQVmFsaWRNaW5kIERldiBDQTAeFw0yNTA3MTcyMjEyMTJa
      Fw0zNTA3MTUyMjEyMTJaMBsxGTAXBgNVBAMMEFZhbGlkTWluZCBEZXYgQ0EwggEi
      MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCdGG304TanKBR3z3u0Snc6+kBN
      piAK4DXhBTFEsCyxzdmH225LOiv16pgZBMq940KdUslExg9/XMy15ozStP/hpTms
      eInyV77s6T2k9fe593fDLvTxrbCzjYJm0JJ1dBgrRUZe2FwiYS+qeTSOFnrAe7y9
      SYLNZ1RJG+bQCJcJr89OvVoCyHkWA2CytgYNupDanuexGQxkBtGZ81s5AtX/dNtL
      prlsuGoNOUGXZ/sPaL452ZVwu1Ha+41zHTSipo/WzwSCmw8xFaEIY5sySbATz9YD
      IqbtaZrj1600sHE804jRDnnCfU5AGTC3fhzPodnWLf4LUdrTxh9fEZMedE3/AgMB
      AAGjgZUwgZIwDAYDVR0TBAUwAwEB/zAdBgNVHQ4EFgQUUcRKwhFGel3xrDZEBofl
      hk0duQAwVgYDVR0jBE8wTYAUUcRKwhFGel3xrDZEBoflhk0duQChH6QdMBsxGTAX
      BgNVBAMMEFZhbGlkTWluZCBEZXYgQ0GCFBkZwhXwPomaoXknxxl0nHAWFRbFMAsG
      A1UdDwQEAwIBBjANBgkqhkiG9w0BAQsFAAOCAQEARD1cMX3e+1/5X3qjDPX3sVNe
      b/02sWhD0RtAAlaSEAlnM4bYx7JLrq45hEgdwBE6aH3tN+HseC2TnLCfp6TeWi5F
      C/lvuJE3dbNlxv+Js4ksBhuqlqFWJm8SEVwUCnRX70M08Pxmr3Lz76NCGjV9xMEL
      LKAmzE4i8Nk53lNJnCEIaH4vOuGymIyFqHgoFLGZ4fW+tdHVUbDKB+8BTtba7xbs
      zCU+LkT1YdvVZzfa6K6wrTY8HWTqSa9fPMyqYvalQJmKJVTI45RqbwfqXzBl4bfe
      ndPc43JRBIoQAj3rbtQvLKB9HUTqD5fvohqA/v9MmdkUnwAWfXe4usRXnh4+BA==
      -----END CERTIFICATE-----
    ''
  ];

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  virtualisation.docker = {
    enable = true;
    extraOptions = "--storage-driver=overlay2";
    extraPackages = [
      pkgs.docker-buildx
      pkgs.docker-compose
    ];
  };
  #programs.niri.enable = true;
  #programs.niri.package = niri.packages.${pkgs.stdenv.hostPlatform.system}.default;
  programs.hyprland.enable = true;
  programs.hyprland.xwayland.enable = true;
  programs.hyprland.withUWSM = true;
  services.gnome.gnome-keyring.enable = true;
  programs.hyprlock.enable = true;
  services.hypridle.enable = true;
  programs.waybar.enable = false;
  environment.sessionVariables.NIXOS_OZONE_WL = "1"; # hint electron apps to use wayland

  # Morning pages: at the first opportunity after 04:00 (awake at 4am, resume
  # from suspend, or first login of the day), open today's daily note in
  # Obsidian and put it front and center on the focused monitor.
  systemd.user.services.morning-pages = {
    description = "Open today's Obsidian daily note front and center";
    path = [ config.programs.hyprland.package pkgs.jq pkgs.coreutils ];
    script = ''
      # May fire right as the session starts; wait for Hyprland to be up.
      sig=""
      for _ in $(seq 150); do
        sig=$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -n1)
        if [ -n "$sig" ] && HYPRLAND_INSTANCE_SIGNATURE=$sig hyprctl monitors >/dev/null 2>&1; then
          break
        fi
        sig=""
        sleep 2
      done
      [ -n "$sig" ] || { echo "no running Hyprland instance; giving up"; exit 1; }
      export HYPRLAND_INSTANCE_SIGNATURE=$sig

      note="Morning pages/$(date +%F)"
      touch "$HOME/ob/first/$note.md"
      uri="obsidian://open?vault=first&file=$(jq -rn --arg f "$note" '$f|@uri')"

      # Launch via Hyprland so Obsidian inherits the session env and outlives
      # this oneshot unit; if already running it just receives the URI.
      hyprctl dispatch "hl.dsp.exec_cmd([[obsidian '$uri']])"

      for _ in $(seq 30); do
        hyprctl clients -j | jq -e 'any(.[]; .class == "obsidian")' >/dev/null && break
        sleep 1
      done
      ws=$(hyprctl activeworkspace -j | jq -r .id)
      hyprctl dispatch "hl.dsp.window.move({ workspace = $ws, window = [[class:obsidian]] })"
      hyprctl dispatch "hl.dsp.focus({ window = [[class:obsidian]] })"
    '';
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "10m";
    };
  };
  systemd.user.timers.morning-pages = {
    description = "Morning pages nag at first opportunity after 04:00";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00";
      Persistent = true; # fire on resume/login if 04:00 was missed
    };
  };

  programs.zsh.enable = true;
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "prohibit-password";
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    extraUpFlags = [
      "--accept-dns"
      "--accept-routes"
    ];
  };
  hardware.brillo.enable = true;

  # Enable the X11 windowing system.
  services.xserver.enable = true;
  services.xserver.displayManager.sessionCommands = ''
    (
      sleep 2
      ${pkgs.xrandr}/bin/xrandr --output eDP --mode 2560x1600 --rate 120 --primary --auto || true
    ) &
  '';

  # Enable the GNOME Desktop Environment.
  services.displayManager.gdm.enable = true;
  #services.displayManager.gdm.wayland = true;
  services.displayManager.gdm.autoSuspend = true;
  services.desktopManager.gnome.enable = true;

  services.xserver.windowManager.xmonad = {
    enable = true;
    enableContribAndExtras = true;
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-wlr
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-gnome
      #pkgs.xdg-desktop-portal-hyprland
    ];

    config = {
      hyprland = {
        default = [ "hyprland" "gtk" ];
        "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
        "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];
        "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
        "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
      };
    };
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable bluetooth
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  services.logind.settings.Login = {
    HandlePowerKey = "suspend-then-hibernate";
    HandleLidSwitch = "suspend";
  };

  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "30min";
  };

  services.upower = {
    enable = true;
    percentageLow = 20;
    percentageCritical = 10;
    # 8% left too little headroom: the hibernate itself takes minutes on a
    # 17 GiB image, and a retry after a failure needs charge to still be there.
    percentageAction = 15;
    criticalPowerAction = "Hibernate";
  };

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = lib.mkForce false;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Local-only "flight recorder" for the built-in camera and microphone.
  # Recordings stay in ~/.local/state/flightrec (mode 0700) and are pruned to
  # whichever of maxSize/maxAgeDays bites first. The unit has PrivateNetwork,
  # so nothing can leave the laptop. See https://git.hunner.dev/hunner/flightrec
  #services.flightrec = {
  #  enable = true;
  #  user = "hunner";

  #  maxSize = "8G";
  #  maxAgeDays = 7;
  #  segmentSeconds = 300;

  #  # Pinned to the Framework 16 internal devices by stable identity, so
  #  # plugging in a USB webcam or the Focusrite never moves the recording.
  #  # Camera: Realtek "Laptop Camera" on usb-0000:c1:00.4-1 (/dev/video0).
  #  # Mic:    ALC295 analog capture on the Ryzen HD Audio controller.
  #  cameraMatch = "^v4l2_input\\.pci-0000_c1_00\\.4-usb-0_1_1\\.0$";
  #  micMatch = "^alsa_input\\.pci-0000_c1_00\\.6\\.analog-stereo$";

  #  # The "hot mic" was +60 dB of analog gain (Capture + Mic Boost both maxed
  #  # by source volume 1.00). The source volume is now 0.15 (~+10.5 dB hardware
  #  # gain, noise floor -50 dB) -- but that turned out to overshoot: measured
  #  # over a real call, active speech sat at -45 to -54 LUFS, about 20 dB below
  #  # what a transcriber wants, and whisper returned [INAUDIBLE] over speech
  #  # that is perfectly clear to a human ear.
  #  #
  #  # +20 dB puts ordinary speech near -25 LUFS. It is applied to PipeWire's
  #  # float samples, so it recovers level without losing information, and it
  #  # affects only flightrec's recordings -- never what Zoom or anything else
  #  # captures. A limiter after the gain keeps the occasional keyboard strike
  #  # from clipping the archive.
  #  #
  #  # To retune: journalctl --user -u flightrec -f | grep "audio level"
  #  audio.gain = 10.0;

  #  # Segments containing motion are renamed with an "_M" suffix, so
  #  #   ls ~/.local/state/flightrec/video/2026-08-17/*_M.mkv
  #  # lists just the clips worth watching. Analysis is a post-pass at nice 19
  #  # and never touches the recording pipelines.
  #  #
  #  # Threshold measured on this camera: a static scene reads 0.5-0.7 from
  #  # sensor noise alone, and an object covering ~1% of the frame moving reads
  #  # 1.75, so 1.0 separates them with room on both sides. Lower it to catch
  #  # subtler movement, raise it if segments get marked with nothing in them.
  #  motion = {
  #    enable = true;
  #    threshold = 1.0;
  #  };
  #};

  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = true;
  services.touchegg.enable = true;

  # sops-nix secrets
  sops.defaultSopsFile = ./secrets/config.yaml;
  sops.age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets.hashedPassword.neededForUsers = true;

  # Define user accounts
  users.groups.ai = {};
  users.users.agents = {
    isSystemUser = true;
    description = "Account for AI agent sandboxing";
    group = "ai";
    home = "/home/agents";
    createHome = true;
    homeMode = "0770";
    extraGroups = [ "docker" "audio" "video" "dialout" "input" ];
    shell = pkgs.zsh;
    packages = with pkgs; [
      nodejs_24
      docker-credential-helpers
      pass
      pkgs.unstable.claude-code
      pkgs.unstable.codex
      #pkgs.codex
      just
      socat
      #pkgs.beads
      gh
      pkgs.unstable.cursor-cli
      pkgs.unstable.opencode
      pkgs.unstable.pi-coding-agent
      pkgs.unstable.grok-build
      python3
      clang
      clangStdenv
      cmake
      just
      dtach
      sox # claude voice
      #lean-ctx
    ];
  };
  users.users.hunner = {
    isNormalUser = true;
    description = "Hunter Haugen";
    extraGroups = [ "docker" "networkmanager" "wheel" "audio" "video" "dialout" "ai" ];
    hashedPasswordFile = config.sops.secrets.hashedPassword.path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqd6VkCyGOaFVfh61+hVKOvYaCZsCChQq3c6rNH/ifG me@hunner.dev"
    ];
    shell = pkgs.zsh;
    packages = with pkgs; [
      alacritty
      rofi
      wofi
      xss-lock
      xlockmore
      dzen2
      arandr
      xclip
      scrot
      xrandr
      xsetroot
      xset
      xev
      hsetroot
      redshift
      pkgs.unstable.code-cursor
      pkgs.unstable.cursor-cli
      pwvucontrol
      pamixer
      #helvum
      #hp15c
      #nonpareil
      kitty # for Hyprland
      kdePackages.dolphin # file browser in hyprland
      cliphist
      xscreensaver
      scarlett2
      alsa-scarlett-gui
      #pkgs.unstable.ndi-6
      #(pkgs.unstable.flameshot.override { enableWlrSupport = true; })
      grim
      slurp
      hyprshot
      hyprpicker
      flameshot
      chromium
      lmstudio
      fzf
      neovim
      asdf-vm
      pinentry-gtk2
      pinentry-gnome3
      gnupg
      pkgs.unstable.firefox-devedition
      nodejs_24
      slack
      mplayer
      ffmpeg-full
      docker-credential-helpers
      jetbrains-toolbox
      pass
      dua
      diff-so-fancy
      zed-editor
      pkgs.unstable.package-version-server
      amdgpu_top
      nixd # for zed
      rust-analyzer # for zed
      nil # for zed
      rustc # for zed
      rustup # for zed
      gcc # for zed
      #ruff # for zed
      #goose-cli
      pkgs.unstable.claude-code
      pkgs.unstable.codex
      #pkgs.codex
      #neofetch
      eww
      quickshell
      fuzzel
      xwayland-satellite
      hyprpaper # for hyprland
      hyprcursor # for hyprland
      nordzy-icon-theme
      nordzy-cursor-theme
      wl-clipboard
      wl-mirror
      onlyoffice-desktopeditors
      calibre
      clipse
      plex-desktop
      signal-desktop
      telegram-desktop
      flyctl
      dtach
      gromit-mpx
      urbanterror
      ghostty
      talon-nix.packages.${pkgs.stdenv.hostPlatform.system}.default
      pyright
      just
      yt-dlp
      ledger-live-desktop
      socat
      #plover-flake.packages.${pkgs.stdenv.hostPlatform.system}.plover-full
      pkgs.unstable.zoom-us
      #pkgs.beads
      #awww.packages.${pkgs.stdenv.hostPlatform.system}.awww
      nix-index # for nix-locate
      sops
      #bitwarden-desktop
      #bitwarden-cli
      itch
      dtach
      whois
      plus42
      sox # claude voice
      pkgs.unstable.pi-coding-agent
      pkgs.unstable.grok-build
      xrandr-invert-colors
      xcalib
      #lean-ctx
      kanata
      obsidian
      zathura
    ];
  };
  # Enable automatic login for the user.
  services.displayManager.autoLogin.enable = false;
  services.displayManager.autoLogin.user = "hunner";

  # Workaround for GNOME autologin: https://github.com/NixOS/nixpkgs/issues/103746#issuecomment-945091229
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  # Install firefox.
  programs.firefox.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Allow dynamic linked binaries
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
    ];
  };


  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
  };

  # Airdrop for linux
  programs.localsend.enable = true;

  # Secure tmux so not /tmp
  programs.tmux.enable = true;
  programs.tmux.secureSocket = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    jq
    yq
    bat
    git
    vim
    emacs-pgtk
    wget
    curl
    htop
    zellij
    file
    ripgrep
    powertop
    fortune
    soteria
    shellcheck
    fd
    framework-tool
    restic
    unzip
    zip
    xdg-utils
    btrbk
    devenv
    lsof
    sg3_utils
    libimobiledevice
    ifuse
  ];

  services.envfs.enable = false;
  services.usbmuxd.enable = true;
  services.clipmenu.enable = true;
  services.picom = {
    enable = true;
    settings = {
      inactive-opacity = 1.0;
      inactive-dim = 0.0;
      inactive-opacity-override = false;
      frame-opacity = 1.0;
      inactive-dim-fixed = false;
      fading = false;  # Optional, if you want to disable fading as well
    };
  };
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    #nix-direnv.package = unstable.nix-direnv;
  };
  programs._1password = {
    enable = true;
  };
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "hunner" "agents" ];
  };
  programs.obs-studio = {
    enable = true;
    package = pkgs.unstable.obs-studio;
    enableVirtualCamera = true;
    plugins = with pkgs.unstable.obs-studio-plugins; [
      wlrobs
      obs-backgroundremoval
      obs-pipewire-audio-capture
      #obs-ndi
      distroav
    ];
  };

  fonts.packages = with pkgs; [
    nerd-fonts.droid-sans-mono
    nerd-fonts.liberation
    nerd-fonts.jetbrains-mono
    nerd-fonts.sauce-code-pro
    nerd-fonts.symbols-only
    liberation_ttf
    font-awesome
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };
  services.pcscd.enable = true;

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 8080 8081 8082 1234 4096 8120 3000 8000 ];
  networking.firewall.allowedUDPPorts = [ 8080 8081 8082 1234 4096 8120 3000 8000 ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;
  systemd.services.upower.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true; # Enable NSS lookup for .local domains
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      workstation = true;
    };
  };
  services.dbus = {
    enable = true;
    packages = [ pkgs.polkit ];
  };
  environment.etc = {
    "1password/custom_allowed_browsers" = {
      text = ''
        firefox-devedition
      '';
      mode = "0755";
    };
  };
  programs.dconf.enable = true;
  security.polkit.enable = true;
  # Restarting polkitd drops session agent registrations (soteria), which
  # breaks 1Password fingerprint unlock until re-login. Defer to reboot.
  systemd.services.polkit.restartIfChanged = false;
  systemd.services."user@".serviceConfig.Delegate = "cpu io memory pids cpuset";

  services.fprintd.enable = true;
  security.pam.services.polkit-1.fprintAuth = true;
  security.pam.services.hyprlock.fprintAuth = true;
  #security.pam.services = {
  #  login.fprintAuth = true;
  #  xscreensaver.fprintAuth = true;
  #  sudo.fprintAuth = true;
  #  #gdm.fprintAuth = true;
  #  gdm-password.fprintAuth = true;
  #};

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

}
# vim: ft=nix ai
