{ stdenv
, cpio
, gzip
, toybox
}:

stdenv.mkDerivation {
  pname = "nullroot-initramfs";
  version = "0.1.0";

  src = ./init;

  dontUnpack = true;

  buildInputs = [ cpio gzip ];

  buildPhase = ''
    mkdir rootfs
    cd rootfs

    mkdir -p bin proc sys dev

    cp ${toybox}/bin/toybox bin/

    chmod +x ${./init}
    cp ${./init} init

    for cmd in sh mount ls mkdir cat echo uname dmesg; do
      ln -s toybox bin/$cmd
    done

    find . -print0 \
      | cpio --null -ov --format=newc \
      | gzip -9 > $out
  '';
}