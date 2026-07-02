{
  description = "Nullroot bootstrap";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      toybox = pkgs.callPackage ./iso/toybox.nix {};
      initramfs = pkgs.callPackage ./iso/initramfs.nix {
        inherit toybox;
      };
      kernel = pkgs.callPackage ./iso/kernel.nix {
        inherit initramfs;
      };
    in {
      packages.${system} = {
        inherit toybox initramfs kernel;
      };
    };
}
