# Testing Nullroot in QEMU

This guide covers building and booting the Nullroot installer inside a QEMU virtual machine — no real hardware required.

## Prerequisites

Install the required tools:

```bash
# NixOS
nix-shell -p qemu ovmf

# Arch Linux
sudo pacman -S qemu-full edk2-ovmf

# Ubuntu/Debian
sudo apt install qemu-system-x86 ovmf
```

---

## Step 1: Build the Kernel Image

```bash
cd /path/to/nullroot
nix build .#kernel --extra-experimental-features "nix-command flakes"
```

The output kernel EFI stub will be at `./result/bzImage`.

---

## Step 2: Create a Virtual Disk

```bash
qemu-img create -f qcow2 nullroot-disk.qcow2 20G
```

---

## Step 3: Locate OVMF Firmware

Find OVMF on your system:

```bash
# NixOS (via nix-shell)
find /nix/store -name "OVMF.fd" 2>/dev/null | head -1

# Arch Linux
ls /usr/share/edk2/x64/OVMF.fd

# Ubuntu/Debian
ls /usr/share/OVMF/OVMF_CODE.fd
```

---

## Step 4: Boot the Installer

### Option A — Direct kernel boot (recommended, fastest)

```bash
qemu-system-x86_64 \
  -enable-kvm \
  -m 4G \
  -smp 4 \
  -drive file=nullroot-disk.qcow2,format=qcow2,if=virtio \
  -kernel result/bzImage \
  -append "console=ttyS0 root=/dev/vda2" \
  -nographic \
  -serial mon:stdio \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0
```

> This boots directly into the Nullroot installer console on your terminal.

### Option B — Full UEFI boot (tests real boot path)

First, copy OVMF firmware and the kernel stub to a directory:

```bash
# Copy writable OVMF vars
cp /usr/share/edk2/x64/OVMF_VARS.fd /tmp/OVMF_VARS.fd   # Arch
# Or:
cp /usr/share/OVMF/OVMF_VARS.fd /tmp/OVMF_VARS.fd         # Ubuntu

# Create a small ESP image with the kernel
mkdir -p /tmp/esp/EFI/BOOT
cp result/bzImage /tmp/esp/EFI/BOOT/BOOTX64.EFI
truncate -s 256M /tmp/esp.img
mkfs.vfat /tmp/esp.img
mcopy -i /tmp/esp.img -s /tmp/esp/. ::
```

Then boot:

```bash
qemu-system-x86_64 \
  -enable-kvm \
  -m 4G \
  -smp 4 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.fd \
  -drive if=pflash,format=raw,file=/tmp/OVMF_VARS.fd \
  -drive file=/tmp/esp.img,format=raw,if=virtio \
  -drive file=nullroot-disk.qcow2,format=qcow2,if=virtio \
  -nographic \
  -serial mon:stdio \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0
```

---

## Step 5: Run the Installer Inside QEMU

Once booted you'll see the Nullroot installer prompt. Run:

```
nullroot-install
```

Follow the installer prompts:

- **Target disk**: enter `/dev/vda` (the virtio disk)
- **Confirm**: type `y`
- **GitHub repo**: enter `justkowal/nullroot` (or your fork)

The installer will:
1. Partition `/dev/vda` into EFI, Root A, Root B, Data
2. Clone your config from GitHub
3. Run `nullroot-detect` to generate a `hardware.nix` for the VM
4. Build the target kernel + rootfs via Nix
5. Flash EROFS to `/dev/vda2` and copy Nix store to the Btrfs subvolumes

> ⚠️ The Nix build step will take 15–40 minutes and requires internet access via the QEMU user networking (`-netdev user`).

---

## Step 6: Boot the Installed System

After installation completes, quit QEMU with `Ctrl-A X` (in serial mode) and reboot into the installed system:

```bash
qemu-system-x86_64 \
  -enable-kvm \
  -m 4G \
  -smp 4 \
  -drive file=nullroot-disk.qcow2,format=qcow2,if=virtio \
  -kernel result/bzImage \
  -append "console=ttyS0 root=/dev/vda2" \
  -nographic \
  -serial mon:stdio \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0
```

> For the full production boot path (reading ACTIVE_SLOT from ESP), use Option B again with the installed disk added as a second drive.

---

## Useful QEMU Controls

| Shortcut | Action |
|----------|--------|
| `Ctrl-A X` | Quit QEMU (serial mode) |
| `Ctrl-A C` | Switch to QEMU monitor |
| `Ctrl-A H` | Show help |

In QEMU monitor:
```
(qemu) quit          # Exit
(qemu) savevm snap1  # Save state
(qemu) loadvm snap1  # Restore state
(qemu) info block    # Show disks
```

---

## Networking Notes

The `-netdev user` mode provides:
- DHCP automatically on `eth0` / `ens*` inside the VM
- Full internet access for `git clone` and Nix downloads
- No host networking configuration needed

If DHCP doesn't auto-configure, manually run inside the VM:

```sh
ifconfig eth0 up
udhcpc -i eth0
```
