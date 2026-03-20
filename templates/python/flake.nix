{
  description = "WIP Analysis Project";

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

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
      self,
      nixpkgs,
      flake-parts,
      pyproject-nix,
      uv2nix,
      pyproject-build-systems,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        {
          config,
          self',
          inputs',
          pkgs,
          system,
          ...
        }:
        let

          pkgs = import inputs.nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
              # cudaSupport = true;
            };
          };

          python = pkgs.python312;
          workspace = inputs.uv2nix.lib.workspace.loadWorkspace {
            workspaceRoot = ./backend;
          };

          overlay = workspace.mkPyprojectOverlay {
            sourcePreference = "wheel";
          };
          editableOverlay = workspace.mkEditablePyprojectOverlay {
            root = "$REPO_ROOT/backend";
          };
          nvidiaOverlay = self: super: {
            torch = super.torch.overrideAttrs (old: {
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
                pkgs.cudaPackages.cudatoolkit
                pkgs.cudaPackages.cudnn
                pkgs.cudaPackages.libcusparse
                pkgs.cudaPackages.libcusparse_lt
                pkgs.cudaPackages.libcufile
                pkgs.cudaPackages.libnvshmem
                pkgs.cudaPackages.nccl
              ];
              autoPatchelfIgnoreMissingDeps = (old.autoPatchelfIgnoreMissingDeps or [ ]) ++ [ "libcuda.so.1" ];
            });
            nvidia-cufile-cu12 = super.nvidia-cufile-cu12.overrideAttrs (old: {
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
                pkgs.rdma-core
              ];
            });
            nvidia-nvshmem-cu12 = super.nvidia-nvshmem-cu12.overrideAttrs (old: {
              nativeBuildInputs = old.nativeBuildInputs ++ [
                pkgs.openmpi
                pkgs.pmix
                pkgs.ucx
                pkgs.libfabric
                pkgs.rdma-core
              ];
            });
            nvidia-cusparse-cu12 = super.nvidia-cusparse-cu12.overrideAttrs (old: {
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
                pkgs.cudaPackages.libnvjitlink
              ];
            });
            nvidia-cusolver-cu12 = super.nvidia-cusolver-cu12.overrideAttrs (old: {
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
                pkgs.cudaPackages.libnvjitlink
                pkgs.cudaPackages.libcusparse
                pkgs.cudaPackages.libcublas
              ];
            });
          };

          # Add your project's package overrides here
          customOverlay = self: super: {
            #pyspark = super.pyspark.overrideAttrs (old: {
            #  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
            #    self.setuptools
            #  ];
            #});
          };

          pythonSets =
            (pkgs.callPackage pyproject-nix.build.packages {
              inherit python;
            }).overrideScope
              (
                pkgs.lib.composeManyExtensions [
                  pyproject-build-systems.overlays.wheel
                  overlay
                  customOverlay
                  # nvidiaOverlay

                ]
              );

        in
        {
          # Bootstrap a new uv app — equivalent to:
          #   nix shell nixpkgs#uv nixpkgs#python3 --command uv init --app --package
          apps.default = {
            type = "app";
            program = pkgs.lib.getExe (pkgs.writeShellApplication {
              name = "init-wip-app";
              runtimeInputs = [ pkgs.uv python ];
              text = ''
                uv init --app --package "$@"
              '';
            });
          };

          devShells.default =
            let
              pythonSet = pythonSets.overrideScope editableOverlay;
              virtualenv = pythonSet.mkVirtualEnv "wip-analysis-dev" workspace.deps.all;
            in
            pkgs.mkShell {
              packages = [
                virtualenv
                pkgs.uv
                # pkgs.jdk17 # Add other dev packages
              ];

              env = {
                UV_NO_SYNC = "1";
                UV_PYTHON = pythonSet.python.interpreter;
                UV_PYTHON_DOWNLOADS = "never";
                # JAVA_HOME = "${pkgs.jdk17}"; # Export Additional Vars
              };

              shellHook = ''
                echo "WIP-ANALYSIS-DEV"
                export REPO_ROOT=$(git rev-parse --show-toplevel)
                unset PYTHONPATH
              '';
            };
          devShells.bootstrap = pkgs.mkShell {
            packages = [
              pkgs.uv
              python
            ];

            shellHook = ''
              echo "WIP-ANALYSIS-BOOTSTRAP"
              if [ ! -f ./backend/pyproject.toml ]; then
                uv init --app --package ./backend
              fi
              echo "Run: cd backend && uv add <pkg>"
              echo "Then: exit && nix develop"

              trap 'git add ./backend/uv.lock ./backend/pyproject.toml 2>/dev/null || true' EXIT
            '';
          };

          packages.default = pythonSets.mkVirtualEnv "wip-analysis-env" workspace.deps.default;

        };

    };
}