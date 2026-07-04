{ stdenv
, pkgs
, initramfs ? null
, hardwareProfile ? null
, configFile ? ./nullroot-kernel.config
, embedInitramfs ? false
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
    llvmPackages.lld
    llvmPackages.clang
    llvmPackages.llvm
  ];

  env = {
    NIX_CFLAGS_COMPILE = "-Wno-unused-command-line-argument";
    KCFLAGS = "-Wno-unused-command-line-argument";
    KAFLAGS = "-Wno-unused-command-line-argument";
    HOSTCFLAGS = "-Wno-unused-command-line-argument";
  };

  buildPhase = ''
    runHook preBuild

    patchShebangs scripts

    # Start from allnoconfig (everything disabled) then merge our minimal fragment
    make LLVM=1 allnoconfig

    # Merge our config fragment on top
    KCONFIG_ALLCONFIG=${configFile} make LLVM=1 allnoconfig

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

    # Embed initramfs if specified, otherwise keep empty for external loading
    ${if embedInitramfs && initramfs != null then ''
      scripts/config --set-str CONFIG_INITRAMFS_SOURCE "${initramfs}/initramfs.cpio.gz"
      scripts/config --enable CONFIG_BLK_DEV_INITRD
    '' else ''
      # Do NOT embed installer initramfs — it's too large (~1 GiB with toolchain).
      # Instead, load it externally via QEMU -initrd or bootloader.
      scripts/config --set-str CONFIG_INITRAMFS_SOURCE ""
      ${if initramfs == null then ''
        scripts/config --disable CONFIG_BLK_DEV_INITRD
      '' else ""}
    ''}

    make LLVM=1 olddefconfig

    # Verify critical options
    echo "=== Verifying config ==="
    grep CONFIG_INITRAMFS_SOURCE .config || true
    grep CONFIG_BLK_DEV_INITRD .config || true
    grep CONFIG_EFI_STUB .config || true
    grep CONFIG_DEVTMPFS .config || true
    echo "========================"

    make LLVM=1 -j$NIX_BUILD_CORES bzImage

    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out
    cp arch/x86/boot/bzImage $out/
    cp .config $out/config
    cp System.map $out/

    # Copy initramfs alongside kernel for external loading
    ${if initramfs != null then ''
      cp ${initramfs}/initramfs.cpio.gz $out/initramfs.cpio.gz
    '' else ""}
  '';
}
