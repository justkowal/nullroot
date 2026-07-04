{ stdenv
, pkgs
, toybox
, uutils
, nushell
, starship
, pkgsStatic
, cacert
, services ? {}
, seatd
, greetd
, tuigreet
, hyprland
, pipewire
, wireplumber
, waybar
, flatpak
, bubblewrap
}:

stdenv.mkDerivation rec {
  pname = "nullroot-target-system";
  version = "0.1.0";

  dontUnpack = true;

  buildPhase = ''
    # Create system directory tree
    mkdir -p $out/{bin,etc/nullroot,etc/nix,etc/ssl/certs,etc/s6/services/getty-ttyS0,etc/s6/services/dhcp-eth0,var,run,tmp,proc,sys,dev,boot,usr/share/udhcpc,nix,home}
    mkdir -p $out/etc/greetd
    mkdir -p $out/etc/skel/.config/{nushell,hypr}

    # Copy statically-linked userspace binaries
    cp ${toybox}/bin/toybox $out/bin/toybox
    cp ${pkgsStatic.busybox}/bin/busybox $out/bin/busybox
    cp ${pkgsStatic.nix}/bin/nix $out/bin/nix
    if [ -f "${uutils}/bin/coreutils" ]; then
      cp "${uutils}/bin/coreutils" "$out/bin/coreutils"
    else
      cp "${uutils}/bin/uutils-coreutils" "$out/bin/coreutils"
    fi
    cp ${nushell}/bin/nu $out/bin/nu
    cp ${starship}/bin/starship $out/bin/starship

    # Copy nullroot-detect, nullroot-install-pkg, nullroot-rebuild, and nullroot-sync scripts
    cp ${./nullroot-detect} $out/bin/nullroot-detect
    chmod +x $out/bin/nullroot-detect
    cp ${./nullroot-install-pkg} $out/bin/nullroot-install-pkg
    chmod +x $out/bin/nullroot-install-pkg
    cp ${./nullroot-rebuild} $out/bin/nullroot-rebuild
    chmod +x $out/bin/nullroot-rebuild
    cp ${./nullroot-sync} $out/bin/nullroot-sync
    chmod +x $out/bin/nullroot-sync

    # Copy Wayland display & audio stack binaries
    cp ${seatd}/bin/seatd $out/bin/seatd
    cp ${greetd}/bin/greetd $out/bin/greetd
    cp ${tuigreet}/bin/tuigreet $out/bin/tuigreet
    
    # Symlink complex graphical & audio packages to target /bin
    ln -sf ${hyprland}/bin/Hyprland $out/bin/Hyprland
    ln -sf ${pipewire}/bin/pipewire $out/bin/pipewire
    ln -sf ${wireplumber}/bin/wireplumber $out/bin/wireplumber
    ln -sf ${waybar}/bin/waybar $out/bin/waybar

    # Symlink Isolation Land sandboxing utilities to target /bin
    ln -sf ${flatpak}/bin/flatpak $out/bin/flatpak
    ln -sf ${bubblewrap}/bin/bwrap $out/bin/bwrap

    # Copy s6 supervision suite binaries
    cp -r ${pkgsStatic.s6}/bin/* $out/bin/

    # Write default /etc/passwd and /etc/group configuration files
    cat > $out/etc/passwd <<'PASSWD_EOF'
root:x:0:0:root:/root:/bin/nu
greeter:x:999:999:greeter:/var/lib/greetd:/bin/sh
PASSWD_EOF

    cat > $out/etc/group <<'GROUP_EOF'
root:x:0:
wheel:x:10:root
video:x:27:root,greeter
audio:x:29:root,greeter
greeter:x:999:
GROUP_EOF

    # Copy SSL CA Certificates (required for Nix / HTTPS downloads on target)
    cp ${cacert}/etc/ssl/certs/ca-bundle.crt $out/etc/ssl/certs/ca-certificates.crt

    # Write target system's Nix configuration
    cat > $out/etc/nix/nix.conf <<'NIXCONF_EOF'
sandbox = false
experimental-features = nix-command flakes
build-users-group =
filter-syscalls = false
NIXCONF_EOF

    # Write target system's default Starship configuration
    cat > $out/etc/starship.toml <<'STARSHIP_EOF'
"$schema" = 'https://starship.rs/config-schema.json'

format = """
[░▒▓](blue)\
$directory\
[▓▒░](fg:blue bg:purple)\
$git_branch\
$git_status\
[▓▒░](fg:purple bg:bright-black)\
$nix_shell\
[▓▒░](fg:bright-black)\
$character"""

[directory]
style = "bg:blue fg:black"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

[git_branch]
symbol = " "
style = "bg:purple fg:black"
format = "[[ $symbol$branch ]($style)]"

[git_status]
style = "bg:purple fg:black"
format = "[($all_status$ahead_behind )($style)]"

[nix_shell]
symbol = "❄️ "
style = "bg:bright-black fg:black"
format = "[[ $symbol$state( \\($name\\)) ]($style)]"

[character]
success_symbol = "[ ➜ ](bold green)"
error_symbol = "[ ➜ ](bold red)"
STARSHIP_EOF

    # Write skeletal default Nushell profiles to automatically load Starship
    cat > $out/etc/skel/.config/nushell/env.nu <<'ENV_EOF'
# Initialize Starship prompt on load
mkdir ~/.cache/starship
starship init nu | save -f ~/.cache/starship/init.nu
ENV_EOF

    cat > $out/etc/skel/.config/nushell/config.nu <<'CONFIG_EOF'
# Load Starship initialization cache
use ~/.cache/starship/init.nu

# General Nushell configurations
$env.config = {
  show_banner: false
  edit_mode: emacs
}
CONFIG_EOF

    # Write greetd display manager configuration
    cat > $out/etc/greetd/config.toml <<'GREETD_EOF'
[default_session]
command = "tuigreet --time --cmd Hyprland --theme 'border=blue;text=magenta;prompt=green;time=red;action=blue;button=yellow'"
user = "greeter"
GREETD_EOF

    # Write skeletal default Hyprland compositor configuration
    cat > $out/etc/skel/.config/hypr/hyprland.conf <<'HYPR_EOF'
# Target-optimized Hyprland bootstrap configuration

# Monitor configuration
monitor=,preferred,auto,1

# Execute essential Wayland display & audio daemons
exec-once = dbus-run-session pipewire &
exec-once = wireplumber &
exec-once = waybar &

# Default userspace tools
$terminal = kitty
$menu = wofi --show drun

# Input setup
input {
    kb_layout = us
    follow_mouse = 1
}

# Basic navigation and launcher bindings (SUPER is main mod key)
$mainMod = SUPER
bind = $mainMod, Q, exec, $terminal
bind = $mainMod, C, killactive,
bind = $mainMod, M, exit,
bind = $mainMod, E, exec, yazi
bind = $mainMod, V, togglefloating,
bind = $mainMod, R, exec, $menu
HYPR_EOF


    # Set up basic sh and POSIX tool symlinks
    ln -sf busybox $out/bin/sh

    # Symlinks to Rust uutils coreutils multicall binary
    for cmd in ls cat echo mkdir cp mv rm ln ps kill sleep \
               clear uname df free id whoami hostname vi sed grep head tail \
               wc find chmod chown mknod dd tar cpio gunzip tr cut env test \
               sort uniq xargs seq basename dirname realpath readlink \
               stat touch date printf; do
      ln -sf coreutils $out/bin/$cmd
    done

    # Symlinks to toybox for non-coreutils system commands
    for cmd in mount umount dmesg blkid blockdev losetup mkswap \
               swapon swapoff partprobe fstype ifconfig route \
               insmod lsmod modinfo lspci ping nc netcat \
               chroot pivot_root switch_root; do
      ln -sf toybox $out/bin/$cmd
    done

    # Write target system's /bin/init script (Stage 2 Boot - initializes s6 supervisor)
    cat > $out/bin/init <<'INIT_EOF'
#!/bin/sh

# Mount proc, sys, dev (if not already mounted by initramfs)
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mkdir -p /dev/pts /dev/shm 2>/dev/null || true
mount -t devpts devpts /dev/pts 2>/dev/null || true
mount -t tmpfs shm /dev/shm 2>/dev/null || true
ln -sf /proc/self/fd /dev/fd 2>/dev/null || true
ln -sf /proc/self/fd/0 /dev/stdin 2>/dev/null || true
ln -sf /proc/self/fd/1 /dev/stdout 2>/dev/null || true
ln -sf /proc/self/fd/2 /dev/stderr 2>/dev/null || true

# Mount tmpfs on /run and /tmp
mount -t tmpfs tmpfs /run -o mode=755,nosuid,nodev 2>/dev/null || true
mount -t tmpfs tmpfs /tmp -o mode=1777,nosuid,nodev 2>/dev/null || true

echo ""
echo "=== NULLROOT OS INSTALLED SYSTEM ==="
echo "Initializing s6 supervision tree..."

# Populate s6 scan directory in /run/service
mkdir -p /run/service
if [ -d /etc/s6/services ] && [ "$(ls -A /etc/s6/services)" ]; then
  cp -a /etc/s6/services/* /run/service/
fi

export PATH=/bin
export HOME=/
export TERM=linux

# Exec s6-svscan to run services and act as PID 1 supervisor
exec s6-svscan /run/service
INIT_EOF
    chmod +x $out/bin/init

    # Compile s6 services declared in Nix
    ${builtins.concatStringsSep "\n" (map (name:
      let
        service = services.${name};
      in
        if service.enable or false then ''
          mkdir -p $out/etc/s6/services/${name}
          cat > $out/etc/s6/services/${name}/run <<'RUN_EOF'
          #!/bin/sh
          echo "Starting service ${name}..."
          ${service.run}
          RUN_EOF
          chmod +x $out/etc/s6/services/${name}/run
        '' else ""
    ) (builtins.attrNames services))}

    # Write udhcpc event script
    cat > $out/usr/share/udhcpc/default.script <<'DHCP_EOF'
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
    ;;
esac
DHCP_EOF
    chmod +x $out/usr/share/udhcpc/default.script

    # Write default system configuration.nix
    cat > $out/etc/nullroot/configuration.nix <<'CONF_EOF'
{
  hostname = "nullroot-host";
  users.root = {
    shell = "sh";
  };
}
CONF_EOF


  '';

  installPhase = ''
    echo "Build phase complete. Directory structure is in $out."
  '';
}
