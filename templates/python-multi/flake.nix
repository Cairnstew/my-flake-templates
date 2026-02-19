{
  description = "Python flake using uv2nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, pyproject-nix, uv2nix, pyproject-build-systems, ... }:
  let
    # First python version is default
    pythonVersions = [ "python312" "python311" "python313" ];
    inherit (nixpkgs) lib;

    forAllSystems = lib.genAttrs lib.systems.flakeExposed;

    workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
    overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };
    editableOverlay = workspace.mkEditablePyprojectOverlay { root = "$REPO_ROOT"; };

    pythonSets = forAllSystems (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in lib.genAttrs pythonVersions (pyName:
        (pkgs.callPackage pyproject-nix.build.packages { python = pkgs.${pyName}; })
          .overrideScope (lib.composeManyExtensions [
            pyproject-build-systems.overlays.wheel
            overlay
          ])
      )
    );

    distPackages = forAllSystems (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in lib.genAttrs pythonVersions (pyName:
        let
          pythonSet = pythonSets.${system}.${pyName};
          python = pkgs.${pyName};
        in pkgs.stdenv.mkDerivation {
          name = "dist-${pyName}";
          src = ./.;
          nativeBuildInputs = [
            pkgs.uv
            python
          ];
          buildPhase = ''
            export HOME=$TMPDIR
            export UV_NO_SYNC=1
            export UV_PYTHON=${python.interpreter}
            export UV_PYTHON_DOWNLOADS=never
            uv build --out-dir dist
          '';
          installPhase = ''
            mkdir -p $out/dist
            cp dist/* $out/dist/
          '';
        }
      )
    );
  in
  {
    devShells = forAllSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        shells = lib.genAttrs pythonVersions (pyName:
          let
            pythonSet = pythonSets.${system}.${pyName}.overrideScope editableOverlay;
            virtualenv = pythonSet.mkVirtualEnv "dev-env-${pyName}" workspace.deps.all;
          in pkgs.mkShell {
            packages = [ virtualenv pkgs.uv ];
            env = {
              UV_NO_SYNC = "1";
              UV_PYTHON = pythonSet.python.interpreter;
              UV_PYTHON_DOWNLOADS = "never";
            };
            shellHook = ''
              unset PYTHONPATH
              export REPO_ROOT=$(git rev-parse --show-toplevel)
            '';
          }
        );
        defaultShell = shells.${lib.head pythonVersions};
      in shells // {
        default = pkgs.mkShell {
          inputsFrom = [ defaultShell ];
          packages = [ pkgs.act ];
          shellHook = ''
            ${defaultShell.shellHook}
            export DOCKER_HOST=$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null || echo "unix:///run/user/$UID/docker.sock")
          '';
        };
      }
    );

    packages = lib.recursiveUpdate
      (forAllSystems (system:
        lib.genAttrs pythonVersions (pyName:
          pythonSets.${system}.${pyName}
            .mkVirtualEnv "env-${pyName}" workspace.deps.default
        )
      ))
      (forAllSystems (system:
        lib.mapAttrs' (pyName: drv:
          lib.nameValuePair "dist-${pyName}" drv
        ) distPackages.${system}
      ));
  };
}