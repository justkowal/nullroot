{ stdenv
, pkgs
, initramfs ? null
, hardwareProfile ? null
}:

let
  kernel = pkgs.linux_latest;
in

stdenv.mkDerivation rec {
  pname = "nullroot-kernel";
  version = kernel.version;

  src = kernel.src;

  nativeBuildInputs = with pkgs; [
    bc
    bison
    flex
    perl
    openssl
    elfutils
    pkg-config
    rsync
    zstd
  ];

  buildPhase = ''
    runHook preBuild

    patchShebangs scripts

    # Start from allnoconfig (everything disabled) then merge our minimal fragment
    make allnoconfig

    # Merge our config fragment on top
    KCONFIG_ALLCONFIG=${./nullroot-kernel.config} make allnoconfig

    # Enable detected storage drivers
    ${if hardwareProfile != null && hardwareProfile.storage ? drivers then
      builtins.concatStringsSep "\n" (map (drv:
        if drv == "nvme" then "scripts/config --enable CONFIG_BLK_DEV_NVME"
        else if drv == "ahci" || drv == "libahci" then "scripts/config --enable CONFIG_SATA_AHCI --enable CONFIG_ATA"
        else "scripts/config --enable CONFIG_${pkgs.lib.replaceStrings ["-"] ["_"] (pkgs.lib.toUpper drv)}"
      ) hardwareProfile.storage.drivers)
    else ""}

    # Enable detected GPU drivers
    ${if hardwareProfile != null && hardwareProfile.gpu ? drivers then
      builtins.concatStringsSep "\n" (map (drv:
        if drv == "i915" then "scripts/config --enable CONFIG_DRM_I915"
        else if drv == "amdgpu" then "scripts/config --enable CONFIG_DRM_AMDGPU"
        else if drv == "nouveau" then "scripts/config --enable CONFIG_DRM_NOUVEAU"
        else if drv == "virtio_gpu" then "scripts/config --enable CONFIG_DRM_VIRTIO_GPU"
        else "scripts/config --enable CONFIG_DRM_${pkgs.lib.replaceStrings ["-"] ["_"] (pkgs.lib.toUpper drv)}"
      ) hardwareProfile.gpu.drivers)
    else ""}

    # Enable detected network drivers
    ${if hardwareProfile != null && hardwareProfile.networking ? drivers then
      builtins.concatStringsSep "\n" (map (drv:
        "scripts/config --enable CONFIG_${pkgs.lib.replaceStrings ["-"] ["_"] (pkgs.lib.toUpper drv)}"
      ) hardwareProfile.networking.drivers)
    else ""}

    # Set initramfs source — must be in .config before build
    ${if initramfs != null then ''
      scripts/config --set-str CONFIG_INITRAMFS_SOURCE "${initramfs}/initramfs.cpio.gz"
    '' else ''
      scripts/config --set-str CONFIG_INITRAMFS_SOURCE ""
      scripts/config --disable CONFIG_BLK_DEV_INITRD
    ''}

    make olddefconfig

    # Verify critical options
    echo "=== Verifying config ==="
    grep CONFIG_INITRAMFS_SOURCE .config || true
    grep CONFIG_BLK_DEV_INITRD .config || true
    grep CONFIG_EFI_STUB .config || true
    grep CONFIG_DEVTMPFS .config || true
    echo "========================"

    make -j$NIX_BUILD_CORES bzImage

    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out
    cp arch/x86/boot/bzImage $out/
    cp .config $out/config
    cp System.map $out/
  '';
}