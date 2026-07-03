{ stdenv, toybox, cpio, gzip }:

stdenv.mkDerivation {
  pname = "nullroot-target-initramfs";
  version = "0.1.0";

  dontUnpack = true;

  nativeBuildInputs = [ cpio gzip ];

  buildPhase = ''
    # Build the initramfs directory tree
    mkdir -p rootfs/{bin,dev,proc,sys,tmp,sysroot}

    # Copy statically-linked toybox
    cp ${toybox}/bin/toybox rootfs/bin/toybox
    chmod +x rootfs/bin/toybox

    # Create symlinks for essential boot applets
    for cmd in sh mount ls cat echo mkdir mknod blkid sleep umount switch_root uname; do
      ln -sf toybox rootfs/bin/$cmd
    done

    # Write target system's initramfs /init script
    cat > rootfs/init <<'INIT_EOF'
#!/bin/sh

# Mount essential file systems for boot
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null

echo ""
echo "=== NULLROOT BOOT STAGE 1 ==="
echo "Kernel: $(uname -r)"
echo "Mounting real root device..."

# Detect and mount the EFI System Partition (FAT32)
EFI_DEV=$(blkid | grep -i 'TYPE="vfat"' | cut -d: -f1 | head -n1)
ACTIVE_SLOT="A"

if [ -n "$EFI_DEV" ]; then
  mkdir -p /efi
  if mount -t vfat "$EFI_DEV" /efi; then
    if [ -f /efi/nullroot.conf ]; then
      . /efi/nullroot.conf
    fi
    umount /efi
  fi
fi

# Fallback root device calculation if not set via cmdline
ROOT_DEV=""
for arg in $(cat /proc/cmdline); do
  case "$arg" in
    root=*)
      ROOT_DEV="''${arg#root=}"
      ;;
  esac
done

if [ -z "$ROOT_DEV" ]; then
  # Calculate ROOT_DEV based on ACTIVE_SLOT
  DISK=""
  if [ -n "$EFI_DEV" ]; then
    DISK=$(echo "$EFI_DEV" | sed -r 's/p?[0-9]+$//')
  else
    DISK="/dev/vda"
  fi
  
  if echo "$DISK" | grep -qE 'nvme|loop'; then
    if [ "$ACTIVE_SLOT" = "B" ]; then
      ROOT_DEV="''${DISK}p3"
    else
      ROOT_DEV="''${DISK}p2"
    fi
  else
    if [ "$ACTIVE_SLOT" = "B" ]; then
      ROOT_DEV="''${DISK}3"
    else
      ROOT_DEV="''${DISK}2"
    fi
  fi
fi

# Wait for root device to appear
echo "Active update slot: $ACTIVE_SLOT"
echo "Waiting for root device $ROOT_DEV to appear..."
for i in 1 2 3 4 5; do
  if [ -b "$ROOT_DEV" ]; then
    break
  fi
  sleep 1
done

# Mount the root device (EROFS) to /sysroot
if mount -t erofs "$ROOT_DEV" /sysroot; then
  echo "Mounted read-only EROFS root device $ROOT_DEV successfully."
  
  # Wait for devices to stabilize and probe data partition
  sleep 1
  echo "Probing writable data partition..."
  DATA_DEV=$(blkid | grep 'TYPE="btrfs"' | cut -d: -f1 | head -n1)
  
  if [ -z "$DATA_DEV" ]; then
    # Fallback to partition 4 of same disk
    DISK=$(echo "$ROOT_DEV" | sed -r 's/p?[0-9]+$//')
    if echo "$ROOT_DEV" | grep -q 'p[0-9]'; then
      DATA_DEV="''${DISK}p4"
    else
      DATA_DEV="''${DISK}4"
    fi
  fi
  
  echo "Found writable data partition: $DATA_DEV"
  
  # Wait for data partition to appear
  for i in 1 2 3 4 5; do
    if [ -b "$DATA_DEV" ]; then
      break
    fi
    sleep 1
  done
  
  if [ -b "$DATA_DEV" ]; then
    echo "Mounting writable subvolumes with ZSTD compression..."
    # Mount @nix subvolume to /sysroot/nix
    mkdir -p /sysroot/nix
    mount -o subvol=@nix,compress=zstd "$DATA_DEV" /sysroot/nix
    
    # Mount @home subvolume to /sysroot/home
    mkdir -p /sysroot/home
    mount -o subvol=@home,compress=zstd "$DATA_DEV" /sysroot/home
    
    # Mount @var subvolume to /sysroot/var
    mkdir -p /sysroot/var
    mount -o subvol=@var,compress=zstd "$DATA_DEV" /sysroot/var
    
    # Mount @flatpak subvolume to /sysroot/var/lib/flatpak
    mkdir -p /sysroot/var/lib/flatpak
    mount -o subvol=@flatpak,compress=zstd "$DATA_DEV" /sysroot/var/lib/flatpak
    
    # Mount /sysroot/etc overlayfs using upper/work dirs inside /sysroot/var
    echo "Configuring overlayfs write path for /etc..."
    mkdir -p /sysroot/var/lib/overlay/etc_upper /sysroot/var/lib/overlay/etc_work
    mount -t overlay overlay -o lowerdir=/sysroot/etc,upperdir=/sysroot/var/lib/overlay/etc_upper,workdir=/sysroot/var/lib/overlay/etc_work /sysroot/etc
    
    # Mount tmpfs on /sysroot/tmp
    mount -t tmpfs tmpfs /sysroot/tmp -o mode=1777,nosuid,nodev
  else
    echo "WARNING: Writable data partition $DATA_DEV not found! Running in transient mode."
    mount -t tmpfs tmpfs /sysroot/tmp -o mode=1777,nosuid,nodev
    mount -t tmpfs tmpfs /sysroot/var -o mode=755,nosuid,nodev
  fi
  
  echo "Transitioning to target system init..."
  exec switch_root /sysroot /bin/init
else
  echo "CRITICAL ERROR: Failed to mount root device $ROOT_DEV!"
  echo "Dropping to recovery shell..."
  exec /bin/sh
fi
INIT_EOF
    chmod +x rootfs/init

    # Create the cpio archive
    (cd rootfs && find . -not -name '.' | sort | cpio -o -H newc --owner=0:0) > base.cpio
    gzip -9 < base.cpio > initramfs.cpio.gz
  '';

  installPhase = ''
    mkdir -p $out
    cp initramfs.cpio.gz $out/
  '';
}
