{ stdenv, fetchurl, bash }:

stdenv.mkDerivation rec {
  pname = "toybox";
  version = "0.8.12";

  src = fetchurl {
    url = "https://landley.net/toybox/downloads/toybox-${version}.tar.gz";
    hash = "sha256-rYipIRM64iMdny34dewL1Cr0QpFFyup9fbngIgim/S4=";
  };

  nativeBuildInputs = [ bash ];
  hardeningDisable = [ "fortify" ];

  # Force fully static binary
  LDFLAGS = "-static";

  patchPhase = ''
    patchShebangs .
  '';

  configurePhase = ''
    # $CC is set by stdenv to the correct compiler in the sandbox.
    # Toybox kconfig uses $(HOSTCC) which defaults to 'cc' — not in pkgsStatic PATH.
    export HOSTCC="$CC"

    make HOSTCC="$CC" defconfig

    grep -n 'SU\|LOGIN\|MKPASSWD' .config || true

    sed -i \
      -e 's/^CONFIG_SU=y/# CONFIG_SU is not set/' \
      -e 's/^CONFIG_LOGIN=y/# CONFIG_LOGIN is not set/' \
      -e 's/^CONFIG_MKPASSWD=y/# CONFIG_MKPASSWD is not set/' \
      -e 's/# CONFIG_SH is not set/CONFIG_SH=y/' \
      .config

    make HOSTCC="$CC" oldconfig
  '';

  buildPhase = ''
    make HOSTCC="$CC" -j$NIX_BUILD_CORES toybox
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp toybox $out/bin/
  '';
}
