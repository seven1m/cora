let
  pkgs = import (builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz") {};
in
pkgs.mkShell {
  packages = with pkgs; [
    autoconf
    automake
    cacert
    git
    gnumake
    libtool
    m4
    openssl
    pkg-config
    stdenv.cc
    zig_0_16
  ];

  shellHook = ''
    export GEM_HOME="$PWD/.gem"
    export GEM_PATH="$PWD/.gem"
  '';
  SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
}
