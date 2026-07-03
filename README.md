# Nullroot OS

A minimal, opinionated Linux distribution built on:

- **EROFS** read-only root with A/B atomic updates
- **Musl libc** + **LLVM/Clang** native compilation
- **uutils-coreutils** (Rust) for POSIX userspace
- **Nushell** + **Starship** default shell environment
- **s6** supervision tree for PID 1 and service management
- **Hyprland** Wayland compositor with **PipeWire** audio
- **Flatpak** + **bubblewrap** for app sandboxing
- **Nix** package manager for declarative user profiles
- **GitHub-synchronized** configuration (system + dotfiles)

---

## Repository Layout

```
nullroot/
├── flake.nix              # ISO builder flake (kernel + initramfs)
├── iso/
│   ├── kernel.nix         # Hardware-profiled minimized Linux build
│   ├── initramfs.nix      # Live installer RAM disk
│   ├── toybox.nix         # Static toybox busybox package
│   └── nullroot-kernel.config  # Base kernel config fragment
├── system/
│   ├── flake.nix          # Target system flake (rootfs closure)
│   ├── system.nix         # Declarative rootfs derivation
│   ├── initramfs.nix      # Stage-1 target boot initramfs
│   ├── nullroot-detect    # Hardware profiler → hardware.nix
│   ├── nullroot-rebuild   # A/B atomic system upgrade tool
│   ├── nullroot-sync      # Push user configs to GitHub
│   └── nullroot-install-pkg  # Declarative user package installer
└── user/                  # Personal dotfiles (synced by nullroot-sync)
    ├── nushell/
    ├── hypr/
    └── starship.toml
```

---

## Prerequisites

A host machine with **Nix** installed and flakes enabled.

```bash
# Enable flakes if not already
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

---

## Building the ISO

### 1. Clone the repository

```bash
git clone https://github.com/justkowal/nullroot
cd nullroot
```

### 2. Build the bootable kernel image (initramfs embedded)

```bash
nix build .#kernel --extra-experimental-features "nix-command flakes"
```

This produces a self-contained EFI stub kernel at `result/bzImage` with the installer initramfs baked in. Build time depends on your machine — the Linux kernel compilation typically takes 15–40 minutes.

### 3. Create a bootable USB drive

```bash
# ⚠️  Replace /dev/sdX with your actual USB device
# Verify with: lsblk
sudo dd if=result/bzImage of=/dev/sdX bs=4M status=progress oflag=sync
```

> **Note**: The `bzImage` EFI stub is directly bootable from UEFI — no additional bootloader is needed. Simply write it to the USB and configure your BIOS to boot from it.

Alternatively, put it on an ESP partition:

```bash
sudo mkdir -p /path/to/efi/EFI/BOOT
sudo cp result/bzImage /path/to/efi/EFI/BOOT/BOOTX64.EFI
```

---

## Installing Nullroot on Real Hardware

### Boot the ISO

1. Insert the USB drive and reboot.
2. Enter BIOS/UEFI and select the USB as the boot device.
3. The kernel will boot directly into the **Nullroot Installer** shell.

### Run the installer

```
nullroot-install
```

The interactive installer will:

1. **Detect disks** — lists all available block devices with sizes
2. **Select target disk** — confirm overwrite of the selected disk
3. **Partition** — creates a GPT layout:
   | Partition | Size | Format | Purpose |
   |-----------|------|--------|---------|
   | p1 | 512 MB | FAT32 | EFI System Partition |
   | p2 | 1.5 GB | EROFS | Root A (active) |
   | p3 | 1.5 GB | EROFS | Root B (inactive, for updates) |
   | p4 | Remaining | Btrfs | Writable data (`@nix`, `@home`, `@var`, `@flatpak`) |
4. **Network** — configures DHCP on `eth0`
5. **Fetch config** — prompts for your GitHub `username/repo` (default: `justkowal/nullroot`), clones latest configs
6. **Hardware detection** — runs `nullroot-detect` to generate `hardware.nix` for the target machine
7. **Nix build** — compiles a target-optimized kernel and rootfs using your cloned config
8. **Flash** — packs rootfs as EROFS, flashes to Root A, copies Nix store to `@nix` subvolume
9. **Boot marker** — writes `ACTIVE_SLOT="A"` to ESP

```
reboot
```

---

## Post-Installation Workflow

### Sync your dotfiles to GitHub

After customizing your Nushell config, Hyprland, etc.:

```sh
nullroot-sync
```

This stages `~/.config/nushell`, `~/.config/hypr`, `~/.config/starship.toml`, and `~/.config/nullroot` into `/etc/nullroot/user/`, commits, and pushes to your GitHub.

### Atomic system upgrade (A/B)

When the system config in your GitHub repo is updated:

```sh
nullroot-rebuild --system
```

This:
1. Pulls latest config from GitHub
2. Builds new system closure with Nix
3. Packs it as EROFS and flashes the **inactive** slot
4. Swaps boot marker on next reboot

### Install user packages declaratively

```sh
nullroot-install-pkg firefox
```

Adds the package to `~/.config/nullroot/user/flake.nix` and switches the Nix profile.

---

## Troubleshooting

| Symptom | Solution |
|---------|----------|
| Kernel panics at boot | Check `root=` kernel cmdline, ensure correct partition |
| Network not available | Manually run `ifconfig eth0 up && udhcpc -i eth0` |
| Nix build fails | Check internet connectivity, try `nix flake update` |
| DHCP fails during install | Use a wired connection; Wi-Fi is not supported in the installer |
