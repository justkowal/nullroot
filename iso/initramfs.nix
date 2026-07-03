{ stdenv, toybox, cpio, gzip, pkgsStatic, cacert, systemSource, git, btrfs-progs, erofs-utils, dialog, toolchainClosure }:

stdenv.mkDerivation {
  pname = "nullroot-initramfs";
  version = "0.1.0";

  dontUnpack = true;

  nativeBuildInputs = [ cpio gzip ];

  buildPhase = ''
    # Build the initramfs directory tree
    mkdir -p rootfs/{bin,dev,proc,sys,tmp,etc,usr/share/udhcpc,etc/udhcpc,etc/ssl/certs,etc/nix,nix/store}

    # Copy statically-linked toybox
    cp ${toybox}/bin/toybox rootfs/bin/toybox
    chmod +x rootfs/bin/toybox

    # Create symlinks for common applets
    ln -sf busybox rootfs/bin/sh
    for cmd in mount ls cat echo mkdir cp mv rm ln dmesg ps kill sleep \
               clear uname df free id whoami hostname vi sed grep head tail \
               wc find chmod chown mknod dd blkid blockdev losetup mkswap \
               swapon swapoff umount partprobe fstype wget \
               nc netcat tar cpio gunzip chroot pivot_root switch_root \
               insmod lsmod modinfo lspci tr cut env test \
               sort uniq xargs seq basename dirname realpath readlink \
               stat touch date printf; do
      ln -sf toybox rootfs/bin/$cmd
    done

    # Symlink networking tools and profiler utilities to Busybox
    for cmd in ifconfig route ping awk tr; do
      ln -sf busybox rootfs/bin/$cmd
    done

    # Copy disk partitioning & formatting tools
    cp ${pkgsStatic.util-linux.bin}/bin/sfdisk rootfs/bin/sfdisk
    cp ${pkgsStatic.dosfstools}/bin/mkfs.fat rootfs/bin/mkfs.fat
    cp ${btrfs-progs}/bin/mkfs.btrfs rootfs/bin/mkfs.btrfs
    cp ${btrfs-progs}/bin/btrfs rootfs/bin/btrfs
    cp ${erofs-utils}/bin/mkfs.erofs rootfs/bin/mkfs.erofs
    cp ${dialog}/bin/dialog rootfs/bin/dialog

    # Copy busybox for udhcpc (DHCP client)
    cp ${pkgsStatic.busybox}/bin/busybox rootfs/bin/busybox
    ln -sf busybox rootfs/bin/udhcpc

    # Copy statically-linked Nix package manager
    cp ${pkgsStatic.nix}/bin/nix rootfs/bin/nix

    # Git is not needed inside initramfs since we fetch configurations via Nix's built-in HTTPS client.

    # Rely on online Nix cache downloads during target build.
    # (Removed copy of toolchain paths to keep initramfs size small enough to boot in standard VM RAM).

    # Copy the target system source files into the initramfs
    mkdir -p rootfs/usr/src/nullroot
    cp -r ${systemSource} rootfs/usr/src/nullroot/system

    # Copy hardware detection utility to /bin
    cp ${systemSource}/nullroot-detect rootfs/bin/nullroot-detect
    chmod +x rootfs/bin/nullroot-detect

    # Copy SSL CA Certificates (required for Nix / HTTPS downloads)
    cp ${cacert}/etc/ssl/certs/ca-bundle.crt rootfs/etc/ssl/certs/ca-certificates.crt

    # Write Nix configuration
    cat > rootfs/etc/nix/nix.conf <<'NIXCONF_EOF'
sandbox = false
experimental-features = nix-command flakes
build-users-group =
NIXCONF_EOF

    # Write udhcpc event script for network interface configuration
    cat > rootfs/usr/share/udhcpc/default.script <<'DHCP_EOF'
#!/bin/sh
case "$1" in
  deconfig)
    ifconfig $interface 0.0.0.0
    ;;
  renew|bound)
    ifconfig $interface $ip netmask $subnet
    if [ -n "$router" ] ; then
      route add default gw $router dev $interface 2>/dev/null || route add default dev $interface gw $router
    fi
    echo -n "" > /etc/resolv.conf
    for i in $dns ; do
      echo "nameserver $i" >> /etc/resolv.conf
    done
    # QEMU User-net DNS fallback and public DNS fallbacks
    echo "nameserver 10.0.2.3" >> /etc/resolv.conf
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    echo "nameserver 1.1.1.1" >> /etc/resolv.conf
    ;;
esac
DHCP_EOF
    chmod +x rootfs/usr/share/udhcpc/default.script
    ln -sf /usr/share/udhcpc/default.script rootfs/etc/udhcpc/default.script

    # Write the nullroot-install script
    cat > rootfs/bin/nullroot-install <<'INSTALLER_EOF'
#!/bin/sh
set -e

echo "=========================================="
echo "      Welcome to the Nullroot Installer   "
echo "=========================================="
echo ""

# 1. Disk detection
echo "Detecting disks..."
disks=""
for d in $(ls /sys/block/ | grep -E '^(sd|vd|nvme|hd)'); do
  if [ -e "/dev/$d" ]; then
    size=$(cat "/sys/block/$d/size")
    size_gb=$((size * 512 / 1024 / 1024 / 1024))
    echo "  - /dev/$d ($size_gb GB)"
    disks="$disks /dev/$d"
  fi
done

if [ -z "$disks" ]; then
  echo "Error: No disks found!"
  exit 1
fi

echo ""
echo -n "Select target disk (e.g. /dev/vda): "
read target_dev

valid=0
for d in $disks; do
  if [ "$d" = "$target_dev" ]; then
    valid=1
  fi
done

if [ "$valid" -eq 0 ]; then
  echo "Error: Invalid selection $target_dev"
  exit 1
fi

echo ""
echo "WARNING: This will erase all data on $target_dev!"
echo -n "Type 'y' to confirm and partition: "
read confirm
if [ "$confirm" != "y" ]; then
  echo "Aborting."
  exit 1
fi

if echo "$target_dev" | grep -qE 'nvme|loop'; then
  part_efi="''${target_dev}p1"
  part_root_a="''${target_dev}p2"
  part_root_b="''${target_dev}p3"
  part_data="''${target_dev}p4"
else
  part_efi="''${target_dev}1"
  part_root_a="''${target_dev}2"
  part_root_b="''${target_dev}3"
  part_data="''${target_dev}4"
fi

# 2. Partitioning
echo ""
echo "Partitioning $target_dev..."
/bin/sfdisk "$target_dev" <<EOF
label: gpt
size=512M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI"
size=1500M, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="Root_A"
size=1500M, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="Root_B"
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="Writable_Data"
EOF

/bin/partprobe "$target_dev" 2>/dev/null || true
sleep 1

# 3. Formatting
echo ""
echo "Formatting EFI partition ($part_efi) as FAT32..."
/bin/mkfs.fat -F32 "$part_efi"

echo "Formatting Writable Data partition ($part_data) as Btrfs..."
/bin/mkfs.btrfs -f "$part_data"

# 4. Creating Btrfs subvolumes
echo ""
echo "Creating Btrfs subvolumes on Writable Data partition..."
mkdir -p /tmp_btrfs
/bin/mount -t btrfs "$part_data" /tmp_btrfs
/bin/btrfs subvolume create /tmp_btrfs/@nix
/bin/btrfs subvolume create /tmp_btrfs/@home
/bin/btrfs subvolume create /tmp_btrfs/@flatpak
/bin/btrfs subvolume create /tmp_btrfs/@var
/bin/umount /tmp_btrfs

# 5. Network Setup & Git Fetch
echo ""
echo "Configuring network (DHCP)..."
/bin/ifconfig eth0 up 2>/dev/null || true
/bin/udhcpc -i eth0 -s /usr/share/udhcpc/default.script -n -q || echo "DHCP failed, continuing..."

# 5. Nix Setup
echo "Mounting target Nix store subvolume..."
mkdir -p /nix
/bin/mount -t btrfs -o subvol=@nix "$part_data" /nix
mkdir -p /nix/var/nix /nix/store /nix/tmp
export TMPDIR=/nix/tmp

echo "Preparing Nix database..."
/bin/nix-store --init 2>/dev/null || true
echo "Ready for Nix builds."

# 6. Fetch OS Configuration from GitHub
echo ""
echo "=========================================="
echo "    Fetching OS Configuration from GitHub "
echo "=========================================="
echo -n "Enter GitHub username/repo [justkowal/nullroot]: "
read repo_url
if [ -z "$repo_url" ]; then
  repo_url="justkowal/nullroot"
fi

echo "Fetching configuration from github:$repo_url..."
JSON_DATA=$(/bin/nix flake metadata "github:$repo_url" --json --extra-experimental-features "nix-command flakes")
STORE_PATH=$(echo "$JSON_DATA" | grep -o '/nix/store/[^"]*')

if [ -z "$STORE_PATH" ]; then
  echo "Error: Failed to fetch configuration metadata!"
  exit 1
fi

echo "Copying configuration from $STORE_PATH..."
rm -rf /usr/src/nullroot
cp -a "$STORE_PATH" /usr/src/nullroot
chmod -R +w /usr/src/nullroot
echo "OS configuration fetched successfully."

echo "Building Nullroot target system directly in live environment..."
export HOME=/tmp

# Execute hardware detection on target to generate hardware.nix
echo "Running target hardware detection..."
mkdir -p /usr/src/nullroot/system
/bin/nullroot-detect > /usr/src/nullroot/system/hardware.nix

echo "Building target system kernel..."
/bin/nix build /usr/src/nullroot#kernel --out-link /tmp/target-kernel --show-trace

echo "Building target system rootfs..."
/bin/nix build /usr/src/nullroot#nullroot-system --out-link /tmp/target-system --show-trace

# Resolve store paths from symlinks
SYSTEM_PATH=$(readlink -f /tmp/target-system)
SYSTEM_DIR=$(basename "$SYSTEM_PATH")
KERNEL_PATH=$(readlink -f /tmp/target-kernel)
KERNEL_DIR=$(basename "$KERNEL_PATH")

# Dump live Nix database
echo "Exporting Nix database..."
/bin/nix-store --dump-db > /tmp/db.dump

# 7. Format and flash read-only EROFS partition
echo "Preparing read-only EROFS root filesystem structure..."
rm -rf /tmp/rootfs
mkdir -p /tmp/rootfs
cp -a "$SYSTEM_PATH/"* /tmp/rootfs/

if [ -d "/usr/src/nullroot/user" ]; then
  echo "Overlaying custom userspace dotfiles from GitHub..."
  mkdir -p /tmp/rootfs/etc/skel/.config
  cp -a /usr/src/nullroot/user/* /tmp/rootfs/etc/skel/.config/ 2>/dev/null || true
fi

echo "Generating read-only EROFS root filesystem image..."
/bin/mkfs.erofs -d /tmp/rootfs /tmp/rootfs.img

echo "Flashing EROFS image to Root A partition ($part_root_a)..."
dd if=/tmp/rootfs.img of="$part_root_a" bs=4M status=progress

# 8. Finalizing Nix store on target
echo "Syncing target Nix store..."
sync
/bin/umount /nix

echo "Mounting target Writable Data partition (@var subvolume)..."
mkdir -p /mnt_var
/bin/mount -t btrfs -o subvol=@var "$part_data" /mnt_var
echo "Populating stateful /var configuration directory..."
cp -a "$SYSTEM_PATH/var/"* /mnt_var/ 2>/dev/null || true
# Create empty overlay directories
mkdir -p /mnt_var/lib/overlay/{etc_upper,etc_work}

echo "Copying cloned GitHub repository to target /etc/nullroot..."
mkdir -p /mnt_var/lib/overlay/etc_upper
cp -a /usr/src/nullroot /mnt_var/lib/overlay/etc_upper/nullroot

/bin/umount /mnt_var

echo "Mounting EFI System Partition..."
mkdir -p /mnt_efi
/bin/mount -t vfat "$part_efi" /mnt_efi
echo "Installing UEFI kernel image..."
mkdir -p /mnt_efi/EFI/BOOT
cp "$KERNEL_PATH/bzImage" /mnt_efi/EFI/BOOT/BOOTX64.EFI

echo "Writing initial A/B boot slot marker..."
cat > /mnt_efi/nullroot.conf <<'BOOTCONF_EOF'
ACTIVE_SLOT="A"
BOOTCONF_EOF

/bin/umount /mnt_efi

echo "Nix target system bootstrap complete."
echo ""
echo "=========================================="
echo "      Nullroot Installation Complete!     "
echo "=========================================="
echo "You can now type 'reboot' to boot into the real Nullroot OS."
INSTALLER_EOF
    chmod +x rootfs/bin/nullroot-install

    # Write /init inline — immune to Nix patchShebangs
    cat > rootfs/init <<'INIT_EOF'
#!/bin/sh

# Mount essential filesystems (devtmpfs automatically populates device nodes)
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null

echo ""
echo "=== NULLROOT OS BOOT ==="
echo "Mounted proc, sys, dev"
echo "Kernel: $(uname -r)"
echo ""
echo "Welcome to Nullroot!"
echo "Type 'nullroot-install' to start the system installation."
echo ""

export PATH=/bin
export HOME=/
export TERM=linux

while true; do
  /bin/busybox getty -n -l /bin/sh 115200 ttyS0
  echo "Console session exited, restarting..."
  sleep 1
done
INIT_EOF
    chmod +x rootfs/init

    # Use a cpio "newc" file list to include device nodes without root privs.
    (cd rootfs && find . -not -name '.' | sort | cpio -o -H newc --owner=0:0) > base.cpio

    # Compress the cpio
    gzip -9 < base.cpio > initramfs.cpio.gz
  '';

  installPhase = ''
    mkdir -p $out
    cp initramfs.cpio.gz $out/
  '';
}