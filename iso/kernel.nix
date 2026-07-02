{ stdenv
, fetchurl
, perl
, bc
, bison
, flex
, openssl
, elfutils
, initramfs
}:

stdenv.mkDerivation rec {
  pname = "nullroot-kernel";
  version = "6.12";

  src = fetchurl {
    url = "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${version}.tar.xz";
    # Replace with real hash
    sha256 = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
  };

  buildInputs = [
    perl
    bc
    bison
    flex
    openssl
    elfutils
  ];

  configurePhase = ''
    make defconfig

    scripts/config --enable EFI_STUB
    scripts/config --enable BLK_DEV_INITRD
    scripts/config --enable DEVTMPFS
    scripts/config --enable DEVTMPFS_MOUNT
    scripts/config --enable PCI
    scripts/config --enable NVME_CORE
    scripts/config --enable BLK_DEV_NVME
    scripts/config --enable EXT4_FS
    scripts/config --enable BTRFS_FS
  '';

  buildPhase = ''
    make -j$NIX_BUILD_CORES \
      CONFIG_INITRAMFS_SOURCE=${initramfs}
  '';

  installPhase = ''
    mkdir -p $out
    cp arch/x86/boot/bzImage $out/
  '';
}
