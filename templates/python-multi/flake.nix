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

  outputs =
    {
      nixpkgs,
      pyproject-nix,
      uv2nix,
      pyproject-build-systems,
      ...
    }:
    let
    pythonVersions = [
      "python310"
      "python311"
      "python312"
    ];
      inherit (nixpkgs) lib;

      format = nixpkgs.formats.yml {};

      forAllSystems = lib.genAttrs lib.systems.flakeExposed;

      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      editableOverlay = workspace.mkEditablePyprojectOverlay {
        root = "$REPO_ROOT";
      };

      pythonSets = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        lib.genAttrs pythonVersions (pyName:
          let
            python = pkgs.${pyName};
          in
          (pkgs.callPackage pyproject-nix.build.packages {
            inherit python;
          }).overrideScope
            (lib.composeManyExtensions [
              pyproject-build-systems.overlays.wheel
              overlay
            ])
        )
      );
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        lib.genAttrs pythonVersions (pyName:
          let
            pythonSet =
              pythonSets.${system}.${pyName}.overrideScope editableOverlay;

            virtualenv =
              pythonSet.mkVirtualEnv "dev-env-${pyName}" workspace.deps.all;
          in
          pkgs.mkShell {
            packages = [
              virtualenv
              pkgs.uv
            ];
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
        )
      );

      packages = forAllSystems (system:
        lib.genAttrs pythonVersions (pyName: {
          default =
            pythonSets.${system}.${pyName}
              .mkVirtualEnv "env-${pyName}" workspace.deps.default;
        })
      );
    };
}