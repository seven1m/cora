{
  description = "Cora - Ruby interpreter in Zig";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/d407951447dcd00442e97087bf374aad70c04cea";

    # Used by shell.nix for plain `nix-shell` support on stable Nix.
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        devShells = {
          default = pkgs.mkShell {
            packages = with pkgs; [
              autoconf
              automake
              cacert
              git
              gnumake
              libtool
              libyaml
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
          };
        };
      });
}