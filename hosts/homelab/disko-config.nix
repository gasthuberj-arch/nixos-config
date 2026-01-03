{
  config,
  lib,
  ...
}: let
  diskMain = builtins.head config.zfs-root.bootDevices;
  diskMirror = builtins.elemAt config.zfs-root.bootDevices 1;
in {
  disko.devices = {
    disk =
      {
        # First NVMe drive - WD Blue SN580
        main = {
          type = "disk";
          device = "/dev/disk/by-id/${diskMain}";
          content = {
            type = "gpt";
            partitions = {
              bios = {
                size = "1M";
                type = "EF02";
              };
              efi = {
                size = "1G";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot/efis/${diskMain}-part2";
                  mountOptions = ["umask=0077"];
                };
              };
              bpool = {
                size = "4G";
                content = {
                  type = "zfs";
                  pool = "bpool";
                };
              };
              rpool = {
                size = "100%";
                content = {
                  type = "zfs";
                  pool = "rpool";
                };
              };
            };
          };
        };

        # Second NVMe drive - Lexar NM790
        mirror = {
          type = "disk";
          device = "/dev/disk/by-id/${diskMirror}";
          content = {
            type = "gpt";
            partitions = {
              bios = {
                size = "1M";
                type = "EF02";
              };
              efi = {
                size = "1G";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot/efis/${diskMirror}-part2";
                  mountOptions = ["umask=0077"];
                };
              };
              bpool = {
                size = "4G";
                content = {
                  type = "zfs";
                  pool = "bpool";
                };
              };
              rpool = {
                size = "100%";
                content = {
                  type = "zfs";
                  pool = "rpool";
                };
              };
            };
          };
        };
      }
      // lib.optionalAttrs (builtins.length config.zfs-root.sataDevices >= 3) {
        # SATA drives for cold storage RAIDZ1
        sata0 = {
          type = "disk";
          device = "/dev/disk/by-id/${builtins.elemAt config.zfs-root.sataDevices 0}";
          content = {
            type = "gpt";
            partitions = {
              zfs = {
                size = "100%";
                content = {
                  type = "zfs";
                  pool = "sata-pool";
                };
              };
            };
          };
        };

        sata1 = {
          type = "disk";
          device = "/dev/disk/by-id/${builtins.elemAt config.zfs-root.sataDevices 1}";
          content = {
            type = "gpt";
            partitions = {
              zfs = {
                size = "100%";
                content = {
                  type = "zfs";
                  pool = "sata-pool";
                };
              };
            };
          };
        };

        sata2 = {
          type = "disk";
          device = "/dev/disk/by-id/${builtins.elemAt config.zfs-root.sataDevices 2}";
          content = {
            type = "gpt";
            partitions = {
              zfs = {
                size = "100%";
                content = {
                  type = "zfs";
                  pool = "sata-pool";
                };
              };
            };
          };
        };
      };

    zpool =
      {
        # Boot pool - mirrored across both NVMe drives
        bpool = {
          type = "zpool";
          mode = "mirror";
          options = {
            ashift = "12";
            autotrim = "on";
            compatibility = "grub2";
          };
          rootFsOptions = {
            acltype = "posixacl";
            canmount = "off";
            compression = "lz4";
            devices = "off";
            normalization = "formD";
            relatime = "on";
            xattr = "sa";
            "com.sun:auto-snapshot" = "false";
          };
          mountpoint = "/boot";

          datasets = {
            nixos = {
              type = "zfs_fs";
              options.mountpoint = "none";
            };
            "nixos/root" = {
              type = "zfs_fs";
              options.mountpoint = "legacy";
              mountpoint = "/boot";
            };
          };
        };

        # Root pool - mirrored across both NVMe drives
        rpool = {
          type = "zpool";
          mode = "mirror";
          options = {
            ashift = "12";
            autotrim = "on";
          };
          rootFsOptions = {
            acltype = "posixacl";
            canmount = "off";
            compression = "zstd";
            dnodesize = "auto";
            normalization = "formD";
            relatime = "on";
            xattr = "sa";
            "com.sun:auto-snapshot" = "false";
          };
          mountpoint = "/";

          datasets = {
            nixos = {
              type = "zfs_fs";
              options.mountpoint = "none";
            };

            # Empty root for impermanence - rolled back on every boot
            "nixos/empty" = {
              type = "zfs_fs";
              options.mountpoint = "legacy";
              mountpoint = "/";
              postCreateHook = "zfs snapshot rpool/nixos/empty@start";
            };

            # Home directories
            "nixos/home" = {
              type = "zfs_fs";
              options.mountpoint = "legacy";
              mountpoint = "/home";
              options."com.sun:auto-snapshot" = "true";
            };

            # Nix store
            "nixos/nix" = {
              type = "zfs_fs";
              options.mountpoint = "legacy";
              mountpoint = "/nix";
              options.atime = "off";
            };

            # Variable data container
            "nixos/var" = {
              type = "zfs_fs";
              options.mountpoint = "none";
            };

            "nixos/var/log" = {
              type = "zfs_fs";
              options.mountpoint = "legacy";
              mountpoint = "/var/log";
              options."com.sun:auto-snapshot" = "true";
            };

            "nixos/var/lib" = {
              type = "zfs_fs";
              options.mountpoint = "legacy";
              mountpoint = "/var/lib";
              options."com.sun:auto-snapshot" = "true";
            };

            # Config persistence
            "nixos/config" = {
              type = "zfs_fs";
              options.mountpoint = "legacy";
              mountpoint = "/etc/nixos";
              options."com.sun:auto-snapshot" = "true";
            };

            # General persistence for impermanence
            "nixos/persist" = {
              type = "zfs_fs";
              options.mountpoint = "legacy";
              mountpoint = "/persist";
              options."com.sun:auto-snapshot" = "true";
            };

            # Application data
            "nixos/apps" = {
              type = "zfs_fs";
              options.mountpoint = "legacy";
              mountpoint = "/apps";
              options = {
                recordsize = "16K"; # Better for databases
                "com.sun:auto-snapshot" = "true";
              };
            };

            # Downloads
            "nixos/downloads" = {
              type = "zfs_fs";
              options.mountpoint = "legacy";
              mountpoint = "/downloads";
              options = {
                recordsize = "128K"; # Better for large files
                "com.sun:auto-snapshot" = "false";
              };
            };

            # Docker volume
            docker = {
              type = "zfs_volume";
              size = "50G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/var/lib/containers";
              };
            };
          };
        };
      }
      // lib.optionalAttrs (builtins.length config.zfs-root.sataDevices >= 3) {
        # Cold tier: SATA RAIDZ1 pool
        sata-pool = {
          type = "zpool";
          mode = "raidz1";
          options = {
            ashift = "12";
          };
          rootFsOptions = {
            acltype = "posixacl";
            canmount = "off";
            compression = "lz4";
            normalization = "formD";
            relatime = "on";
            xattr = "sa";
            atime = "off";
            "com.sun:auto-snapshot" = "false";
          };
          mountpoint = null;

          datasets = {
            # Media storage
            media = {
              type = "zfs_fs";
              options.mountpoint = "legacy";
              mountpoint = "/media";
              options = {
                recordsize = "128K";
                "com.sun:auto-snapshot" = "true";
              };
            };

            # Pictures
            pictures = {
              type = "zfs_fs";
              options.mountpoint = "legacy";
              mountpoint = "/pictures";
              options = {
                recordsize = "128K";
                "com.sun:auto-snapshot" = "true";
              };
            };

            # Backups
            backups = {
              type = "zfs_fs";
              options.mountpoint = "legacy";
              mountpoint = "/backups";
              options = {
                "com.sun:auto-snapshot" = "true";
              };
            };

            # Archive/cold storage
            archive = {
              type = "zfs_fs";
              options.mountpoint = "legacy";
              mountpoint = "/archive";
              options = {
                recordsize = "128K";
                "com.sun:auto-snapshot" = "true";
              };
            };
          };
        };
      };
  };
}
