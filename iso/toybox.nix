{ stdenv
, fetchurl
, musl
}:

stdenv.mkDerivation rec {
  pname = "toybox";
  version = "0.8.12";

  src = fetchurl {
    url = "https://landley.net/toybox/downloads/toybox-${version}.tar.gz";
    # Replace with real hash after first nix-prefetch-url
    sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  buildInputs = [ musl ];

  configurePhase = ''
    make defconfig
  '';

  buildPhase = ''
    make -j$NIX_BUILD_CORES
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp toybox $out/bin/
  '';
}
