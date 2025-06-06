# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "thunderbolt" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "none";
      fsType = "tmpfs";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/E270-3DFB";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };

  fileSystems."/home" =
    { device = "/dev/disk/by-uuid/8be833f2-6247-49e4-a6cb-f8ebe69619f6";
      fsType = "btrfs";
      options = [ "subvol=home" ];
    };

  boot.initrd.luks.devices."cryptroot".device = "/dev/disk/by-uuid/2fade11e-8347-415d-8629-0578a7c8d534";

  fileSystems."/nix" =
    { device = "/dev/disk/by-uuid/8be833f2-6247-49e4-a6cb-f8ebe69619f6";
      fsType = "btrfs";
      options = [ "subvol=nix" ];
    };

  fileSystems."/persist" =
    { device = "/dev/disk/by-uuid/8be833f2-6247-49e4-a6cb-f8ebe69619f6";
      fsType = "btrfs";
      options = [ "subvol=persist" ];
    };

  fileSystems."/var/lib" =
    { device = "/dev/disk/by-uuid/8be833f2-6247-49e4-a6cb-f8ebe69619f6";
      fsType = "btrfs";
      options = [ "subvol=var/lib" ];
    };

  fileSystems."/var/log" =
    { device = "/dev/disk/by-uuid/8be833f2-6247-49e4-a6cb-f8ebe69619f6";
      fsType = "btrfs";
      options = [ "subvol=var/log" ];
    };

  #swapDevices =
  #  [ { device = "/dev/disk/by-uuid/4ad150c5-5d21-422c-8038-18952e1d999d"; }
  #  ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlp1s0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
