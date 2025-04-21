# Config for framework 16
# sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko/latest -- --mode destroy,format,mount disko.nix
{
  disko.devices = {
    disk = {
      nvme0n1 = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              label = "boot";
              name = "ESP";
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" "defaults" ];
              };
            };
            cryptswap = {
              size = "70G";
	      type = "8300";
              content = {
                type = "luks";
		name = "cryptswap";
		passwordFile = "/tmp/secret.key";
		content = {
		  type = "swap";
		  resumeDevice = true;
		};
              };
            };
            cryptroot = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
		passwordFile = "/tmp/secret.key";
                settings = {
                  allowDiscards = true;
                  crypttabExtraOpts = [ "no-read-workqueue" "no-write-workqueue" ];
                };
                content = {
                  type = "btrfs";
                  extraArgs = [ "-L" "nixos" "-f" ];
                  subvolumes = {
                    "/persist" = {
		      mountpoint = "/persist";
		      mountOptions = [ "compress=zstd" "noatime" "ssd" "space_cache=v2" ];
		    };
                    "/home" = {
		      mountpoint = "/home";
		      mountOptions = [ "compress=zstd" "noatime" "ssd" "space_cache=v2" ];
		    };
                    "/var/log" = {
		      mountpoint = "/var/log";
		      mountOptions = [ "compress=zstd" "noatime" "ssd" "space_cache=v2" ];
		    };
                    "/var/lib" = {
		      mountpoint = "/var/lib";
		      mountOptions = [ "compress=zstd" "noatime" "ssd" "space_cache=v2" ];
		    };
                    "/nix" = {
		      mountpoint = "/nix";
		      mountOptions = [ "compress=zstd" "noatime" "ssd" "space_cache=v2" ];
		    };
		    "/swap" = {
		      mountpoint = "/swap";
		      swap.swapfile.size = "70G";
		    };
		  };
                };
              };
            };
          };
        };
      };
    };
    nodev = {
      "/" = {
        fsType = "tmpfs";
	mountOptions = [
	  "defaults"
	  "size=4G"
	  "mode=755"
	];
      };
    };
  };

  filesystems."/persist".neededForBoot = true;
  filesystems."/var/log".neededForBoot = true;
}
