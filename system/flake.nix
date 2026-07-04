{
  description = "Nullroot OS - Target System Configuration";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";

      # Base Musl package set
      basePkgs = (import nixpkgs { inherit system; }).pkgsMusl;

      # Load hardware profile if it exists, otherwise fallback to generic defaults
      hardwareProfile = if builtins.pathExists ./hardware.nix then import ./hardware.nix else {
        cpu = { vendor = "Generic"; cores = 1; flags = []; };
        gpu = { intel = false; amd = false; nvidia = false; virtio = false; drivers = []; };
        storage = { nvme = false; ahci = false; drivers = []; };
        networking = { ethernet = false; wifi = false; drivers = []; };
      };

      # Custom target-optimized dynamic LLVM stdenv
      baseStdenv = basePkgs.llvmPackages.stdenv;
      customStdenv = baseStdenv // {
        mkDerivation = args: baseStdenv.mkDerivation (finalAttrs:
          let
            attrs = if builtins.isFunction args then args finalAttrs else args;
          in
            attrs // {
              NIX_CFLAGS_COMPILE = (attrs.NIX_CFLAGS_COMPILE or []) ++ [ "-march=native" "-O3" "-flto" ];
              NIX_LDFLAGS = (attrs.NIX_LDFLAGS or []) ++ [ "-flto" ];
            }
        );
      };

      # Custom target-optimized static LLVM stdenv
      baseStdenvStatic = basePkgs.pkgsStatic.llvmPackages.stdenv;
      customStdenvStatic = baseStdenvStatic // {
        mkDerivation = args: baseStdenvStatic.mkDerivation (finalAttrs:
          let
            attrs = if builtins.isFunction args then args finalAttrs else args;
          in
            attrs // {
              NIX_CFLAGS_COMPILE = (attrs.NIX_CFLAGS_COMPILE or []) ++ [ "-march=native" "-O3" "-flto" ];
              NIX_LDFLAGS = (attrs.NIX_LDFLAGS or []) ++ [ "-flto" ];
            }
        );
      };

      # 1. Statically-linked userspace core
      toybox = basePkgs.callPackage ../iso/toybox.nix {
        stdenv = customStdenvStatic;
      };

      # 2. Target system's initramfs (mounts real root disk and switches root)
      initramfs = basePkgs.callPackage ./initramfs.nix {
        stdenv = customStdenvStatic;
        inherit toybox;
      };

      # 3. Target system's kernel (embeds target initramfs)
      kernel = basePkgs.callPackage ../iso/kernel.nix {
        stdenv = basePkgs.llvmPackages.stdenv;
        pkgs = basePkgs;
        configFile = ./nullroot-system-kernel.config;
        inherit initramfs hardwareProfile;
        embedInitramfs = true;
      };

      # 4. Target-optimized static uutils-coreutils multicall binary
      uutils = (basePkgs.pkgsStatic.uutils-coreutils.override {
        stdenv = customStdenvStatic;
      }).overrideAttrs (oldAttrs: {
        doCheck = false;
      });

      # Target-optimized static Nushell
      nushell = (basePkgs.pkgsStatic.nushell.override {
        stdenv = customStdenvStatic;
      }).overrideAttrs (oldAttrs: {
        doCheck = false;
      });

      # Target-optimized static Starship
      starship = (basePkgs.pkgsStatic.starship.override {
        stdenv = customStdenvStatic;
      }).overrideAttrs (oldAttrs: {
        doCheck = false;
      });

      # Declarative system services supervised by s6
      services = {
        getty-ttyS0 = {
          enable = true;
          run = "exec /bin/busybox getty -n -l /bin/nu 115200 ttyS0";
        };
        dhcp-eth0 = {
          enable = true;
          run = "exec /bin/busybox udhcpc -i eth0 -f";
        };
        seatd = {
          enable = true;
          run = "exec /bin/seatd -g video";
        };
        greetd = {
          enable = true;
          run = "exec /bin/greetd";
        };
      };

      # 5. Target system's rootfs closure (installed onto the EXT4/Btrfs partition)
      nullroot-system = basePkgs.callPackage ./system.nix {
        stdenv = customStdenv;
        pkgsStatic = basePkgs.pkgsStatic;
        inherit toybox uutils nushell starship services;

        # Pass GUI & audio stack packages
        seatd = basePkgs.seatd;
        greetd = basePkgs.greetd;
        tuigreet = basePkgs.tuigreet;
        hyprland = basePkgs.hyprland;
        pipewire = basePkgs.pipewire;
        wireplumber = basePkgs.wireplumber;
        waybar = basePkgs.waybar;

        # Pass Isolation Land sandboxing tools
        flatpak = basePkgs.flatpak;
        bubblewrap = basePkgs.bubblewrap;
      };
    in {
      packages.${system} = {
        inherit kernel initramfs nullroot-system;
        default = nullroot-system;
      };
    };
}
