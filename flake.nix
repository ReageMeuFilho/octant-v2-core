{
  description = "The decentralised governance system from Golem Foundation";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/master";
    flake-utils.url = "github:numtide/flake-utils";
    foundry.url = "github:shazow/foundry.nix/monthly";
  };

  outputs = {nixpkgs, flake-utils, foundry, ... }: flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ foundry.overlay ];
      };
      darwinInputs = pkgs.lib.optionals pkgs.stdenv.isDarwin [ pkgs.xcbuild ];
    in {
      devShells.default = pkgs.mkShell {
        buildInputs = [
          pkgs.solc
          pkgs.foundry-bin
          pkgs.nodejs_22.pkgs.yarn
          pkgs.nodejs_22
          pkgs.act # enables running GH pipeline locally
        ] ++ darwinInputs;
      };
    });
}
