{
  description = "Nullroot OS — EROFS/A-B Linux distribution with Musl/LLVM/Rust userspace";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # Load hardware profile if it exists, otherwise fallback to generic defaults
      # During installation, this will load the generated ./system/hardware.nix
      hardwareProfile = if builtins.pathExists ./system/hardware.nix then import ./system/hardware.nix else {
        cpu = { vendor = "Generic"; cores = 1; flags = []; };
        gpu = { intel = false; amd = false; nvidia = false; virtio = false; drivers = []; };
        storage = { nvme = false; ahci = false; drivers = []; };
        networking = { ethernet = false; wifi = false; drivers = []; };
      };

      # Custom target-optimized dynamic LLVM stdenv
      baseStdenv = pkgs.pkgsMusl.llvmPackages.stdenv;
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

      # Standard static toybox (uses standard GCC-based pkgsStatic to avoid compiler-rt/gcc_eh link issues)
      toybox = pkgs.pkgsStatic.callPackage ./iso/toybox.nix { };

      # Target system packages
      uutils = pkgs.pkgsStatic.uutils-coreutils;
      nushell = pkgs.pkgsStatic.nushell;
      starship = pkgs.pkgsStatic.starship;

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

      # Base Musl package set
      baseMusl = pkgs.pkgsMusl;

      # Closure info containing the toolchain and compile-time dependencies to bundle in ISO
      toolchainClosure = pkgs.closureInfo {
        rootPaths = [
          baseMusl.llvmPackages.stdenv.cc
          baseMusl.rustc
          baseMusl.cargo
          baseMusl.bison
          baseMusl.flex
          baseMusl.bc
          baseMusl.perl
          baseMusl.openssl.dev
          baseMusl.elfutils.dev
          baseMusl.pkg-config
          baseMusl.zstd.dev
          baseMusl.cpio
          baseMusl.gzip
        ];
      };

      initramfs = pkgs.callPackage ./iso/initramfs.nix {
        inherit toybox toolchainClosure;
        git = pkgs.pkgsStatic.git.overrideAttrs (old: { doCheck = false; doInstallCheck = false; });
        btrfs-progs = pkgs.pkgsStatic.btrfs-progs;
        erofs-utils = pkgs.pkgsStatic.erofs-utils;
        
        dialog = pkgs.pkgsStatic.dialog.overrideAttrs (old: {
          configureFlags = (old.configureFlags or []) ++ [
            "--without-shared"
            "--without-libtool"
          ];
          env = (old.env or {}) // {
            LDFLAGS = "-static";
          };
        });
        
        systemSource = ./system;
      };

      # Kernel (passes hardwareProfile to optimize configuration, compiled with host LLVM stdenv)
      kernel = pkgs.callPackage ./iso/kernel.nix {
        stdenv = pkgs.llvmPackages.stdenv;
        pkgs = pkgs;
        inherit initramfs hardwareProfile;
      };

      # Target system rootfs closure
      nullroot-system = pkgs.callPackage ./system/system.nix {
        stdenv = customStdenv;
        pkgsStatic = pkgs.pkgsStatic;
        inherit toybox uutils nushell starship services;

        # Pass GUI & audio stack packages
        seatd = pkgs.seatd;
        greetd = pkgs.greetd;
        tuigreet = pkgs.tuigreet;
        hyprland = pkgs.hyprland;
        pipewire = pkgs.pipewire;
        wireplumber = pkgs.wireplumber;
        waybar = pkgs.waybar;

        # Pass Isolation Land sandboxing tools
        flatpak = pkgs.flatpak;
        bubblewrap = pkgs.bubblewrap;
      };
    in {
      packages.${system} = {
        inherit toybox initramfs kernel nullroot-system;
        default = nullroot-system;
      };
    };
}