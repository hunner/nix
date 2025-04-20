{
  disko.devices = {
    disk = {
      vda = {
        device = "/dev/vda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1G";
              type = "EF02"; # BIOS boot partition
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/boot";
              };
            };
            swap = {
              size = "8G";
              content = {
                type = "swap";
                randomEncryption = true;
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };
    };
    zpool = {
      rpool = {
        type = "zpool";
        rootFsOptions = {
          acltype = "posixacl";
          compression = "lz4";
          dnodesize = "auto";
          normalization = "formD";
          relatime = "on";
          xattr = "sa";
        };
        options = {
          ashift = "12";
          autotrim = "on";
        };
        datasets = {
          "local/root" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              canmount = "noauto";
            };
            mountpoint = "/";
            postCreateHook = ''
              zfs snapshot rpool/local/root@blank
              zfs rollback rpool/local/root@blank
            '';
          };
          "local/nix" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/nix";
          };
          "safe/persist" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/persist";
          };
          "safe/home" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/home";
          };
          "local/var" = {
            type = "zfs_fs";
            options = {
              mountpoint = "none";
              canmount = "off";
            };
          };
          "local/var/lib" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/var/lib";
          };
          "local/var/log" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/var/log";
          };
        };
      };
    };
  };
}
