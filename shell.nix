let
  pkgs = import (builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz") {};
in
pkgs.mkShell {
  packages = with pkgs; [
    autoconf
    automake
    git
    gnumake
    libtool
    m4
    openssl
    pkg-config
    stdenv.cc
    zig_0_16
  ];
}
