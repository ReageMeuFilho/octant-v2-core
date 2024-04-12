{
  description = "The decentralised governance system from Golem Foundation";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/23.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {nixpkgs, flake-utils, ... }: flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs { inherit system; };
      darwinInputs = pkgs.lib.optionals pkgs.stdenv.isDarwin [ pkgs.xcbuild ];
    in {
      devShells.default = pkgs.mkShell {
        buildInputs = [
          pkgs.nodejs
          pkgs.yarn
        ] ++ darwinInputs;
      };
    });
}
