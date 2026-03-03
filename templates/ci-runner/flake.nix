{
  description = "CI steps";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        apps = {

          # --- CI Steps ---
          # Run with: nix run .#lint
          lint = {
            type = "app";
            program = toString (pkgs.writeShellScript "lint" ''
              set -euo pipefail
              echo "Running linter..."
              # your lint command here, e.g.:
              # ${pkgs.pylint}/bin/pylint ./src
            '');
          };

          # Run with: nix run .#test
          test = {
            type = "app";
            program = toString (pkgs.writeShellScript "test" ''
              set -euo pipefail
              echo "Running tests..."
              # your test command here, e.g.:
              # ${pkgs.python3}/bin/python -m pytest ./tests
            '');
          };

          # Run with: nix run .#build
          build = {
            type = "app";
            program = toString (pkgs.writeShellScript "build" ''
              set -euo pipefail
              echo "Building..."
              # your build command here, e.g.:
              # ${pkgs.go}/bin/go build ./...
            '');
          };

          # Run with: nix run .#ci  (runs all steps in sequence)
          ci = {
            type = "app";
            program = toString (pkgs.writeShellScript "ci" ''
              set -euo pipefail
              echo "==> lint"
              ${self.apps.${system}.lint.program}
              echo "==> test"
              ${self.apps.${system}.test.program}
              echo "==> build"
              ${self.apps.${system}.build.program}
              echo "All CI steps passed."
            '');
          };

        };
      });
}
