# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, nixos-generators }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        gcloud = pkgs.google-cloud-sdk.withExtraComponents (with pkgs.google-cloud-sdk.components; [
          gke-gcloud-auth-plugin
          gcloud-man-pages
        ]);
      in
      {
        # Dev shell with all the tools you need
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            opentofu
            gcloud
            awscli2
          ];

          shellHook = ''
            KEY_FILE="ccws-key.json"
            if [ -f "$KEY_FILE" ]; then
              echo "🔑 Found service account key: $KEY_FILE"
              gcloud auth activate-service-account --key-file="$KEY_FILE"
              echo "✅ Service account activated!"
            else
              echo "⚠️ No service account key found → run: gcloud auth login"
            fi
          '';
        };

        # Deploy to GCP
        apps.deploy-gcp = {
          type = "app";
          program = toString (pkgs.writeShellScript "deploy-gcp" ''
            set -euo pipefail

            PROJECT=''${PROJECT:?set PROJECT}
            BUCKET=''${BUCKET:?set BUCKET}
            REGION=''${REGION:-us-central1}

            echo "==> Building GCE image..."
            nix build .#gce-image --print-build-logs
            IMAGE_PATH=$(readlink -f result/*.tar.gz)
            IMAGE_HASH=$(nix hash path result/ | head -c 12)

            echo "==> Running OpenTofu..."
            cd terraform/deployments/gcp
            tofu init -upgrade
            tofu apply \
              -var="project=$PROJECT" \
              -var="bucket=$BUCKET" \
              -var="region=$REGION" \
              -var="image_path=$IMAGE_PATH" \
              -var="image_hash=$IMAGE_HASH" \
              -auto-approve
          '');
        };

        # Deploy to AWS
        apps.deploy-aws = {
          type = "app";
          program = toString (pkgs.writeShellScript "deploy-aws" ''
            set -euo pipefail

            BUCKET=''${BUCKET:?set BUCKET}
            REGION=''${REGION:-us-east-1}

            echo "==> Building Amazon image..."
            nix build .#amazon-image --print-build-logs
            IMAGE_PATH=$(readlink -f result/*.vhd)
            IMAGE_HASH=$(nix hash path result/ | head -c 12)

            echo "==> Running OpenTofu..."
            cd terraform/deployments/aws
            tofu init -upgrade
            tofu apply \
              -var="bucket=$BUCKET" \
              -var="region=$REGION" \
              -var="image_path=$IMAGE_PATH" \
              -var="image_hash=$IMAGE_HASH" \
              -auto-approve
          '');
        };
      }
    ) // {
      # NixOS configuration shared between clouds
      nixosConfigurations.myvm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/google-compute-image.nix"
          ./nixos/configuration.nix
        ];
      };

      # GCE image (used by deploy-gcp)
      packages.x86_64-linux.gce-image =
        self.nixosConfigurations.myvm.config.system.build.googleComputeImage;

      # Amazon image (used by deploy-aws)
      packages.x86_64-linux.amazon-image =
        nixos-generators.nixosGenerate {
          system = "x86_64-linux";
          format = "amazon";
          modules = [ ./nixos/configuration.nix ];
        };
    };
}
