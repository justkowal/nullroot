{
  description = "Nullroot OS — EROFS/A-B Linux distribution with Musl/LLVM/Rust userspace";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      toybox = pkgs.pkgsStatic.callPackage ./iso/toybox.nix { };
      nullroot-system = pkgs.callPackage ./system/system.nix {
        inherit toybox;
        pkgsStatic = pkgs.pkgsStatic;
        uutils = pkgs.pkgsStatic.uutils-coreutils;
        nushell = pkgs.pkgsStatic.nushell;
        starship = pkgs.pkgsStatic.starship;
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
        
        # Override dialog to forcefully disable shared linking and intercept gcc calls
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

      kernel = pkgs.callPackage ./iso/kernel.nix {
        inherit initramfs;
      };
    in {
      packages.${system} = {
        inherit toybox initramfs kernel nullroot-system;
      };
    };
}