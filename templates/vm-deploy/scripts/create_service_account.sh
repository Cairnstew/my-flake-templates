#!/usr/bin/env bash
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
PROJECT=${PROJECT:-}
BUCKET=${BUCKET:-}
TFSTATE_BUCKET="${PROJECT}-tfstate"
GITHUB_REPO="${GITHUB_REPO:-}"
SERVICE_ACCOUNT="github-actions"
POOL_NAME="github-pool"
PROVIDER_NAME="github-provider"
# ─────────────────────────────────────────────────────────────────────────────

# ── Helpers ───────────────────────────────────────────────────────────────────
prompt() {
  local var="$1" prompt="$2" default="${3:-}"
  if [ -z "${!var:-}" ]; then
    if [ -n "$default" ]; then
      read -rp "$prompt [$default]: " val
      eval "$var=\"${val:-$default}\""
    else
      read -rp "$prompt: " val
      while [ -z "$val" ]; do
        echo "  ✗ This field is required."
        read -rp "$prompt: " val
      done
      eval "$var=\"$val\""
    fi
  fi
}

check_gh_cli() {
  if command -v gh &>/dev/null && gh auth status &>/dev/null; then
    echo "true"
  else
    echo "false"
  fi
}
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║     GCP GitHub Actions Setup Script         ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Collect inputs ────────────────────────────────────────────────────────────
prompt PROJECT      "GCP Project ID"
prompt BUCKET       "GCS bucket name for NixOS images"
prompt GITHUB_REPO  "GitHub repo (e.g. myorg/myrepo)"

read -rp "SSH public key for NixOS VM (paste key or leave blank to skip): " SSH_PUBLIC_KEY
read -rp "VM name [myvm]: " VM_NAME
VM_NAME="${VM_NAME:-myvm}"
read -rp "GCP region [us-central1]: " REGION
REGION="${REGION:-us-central1}"
read -rp "GCP zone [us-central1-a]: " ZONE
ZONE="${ZONE:-us-central1-a}"
read -rp "Machine type [e2-small]: " MACHINE_TYPE
MACHINE_TYPE="${MACHINE_TYPE:-e2-small}"

TFSTATE_BUCKET="${PROJECT}-tfstate"
SA_EMAIL="${SERVICE_ACCOUNT}@${PROJECT}.iam.gserviceaccount.com"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT" --format="value(projectNumber)")

echo ""
echo "==> Project:         $PROJECT"
echo "==> Project number:  $PROJECT_NUMBER"
echo "==> Service account: $SA_EMAIL"
echo "==> GitHub repo:     $GITHUB_REPO"
echo "==> Image bucket:    $BUCKET"
echo "==> State bucket:    $TFSTATE_BUCKET"
echo ""

# ── 1. Service account ────────────────────────────────────────────────────────
echo "==> [1/8] Creating service account..."
if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT" &>/dev/null; then
  echo "    Already exists, skipping."
else
  gcloud iam service-accounts create "$SERVICE_ACCOUNT" \
    --display-name="GitHub Actions" \
    --project="$PROJECT"
fi

# ── 2. IAM roles ──────────────────────────────────────────────────────────────
echo "==> [2/8] Granting IAM roles..."
for ROLE in roles/compute.admin roles/storage.admin roles/iam.serviceAccountUser; do
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="$ROLE" \
    --condition=None \
    --quiet
  echo "    Granted $ROLE"
done

# ── 3. GCS buckets ────────────────────────────────────────────────────────────
echo "==> [3/8] Creating GCS buckets..."

if gsutil ls -b "gs://${BUCKET}" &>/dev/null; then
  echo "    Image bucket already exists, skipping."
else
  gsutil mb -p "$PROJECT" "gs://${BUCKET}"
  echo "    Created image bucket: gs://${BUCKET}"
fi

if gsutil ls -b "gs://${TFSTATE_BUCKET}" &>/dev/null; then
  echo "    State bucket already exists, skipping."
else
  gsutil mb -p "$PROJECT" "gs://${TFSTATE_BUCKET}"
  echo "    Created state bucket: gs://${TFSTATE_BUCKET}"
fi

gsutil iam ch "serviceAccount:${SA_EMAIL}:roles/storage.admin" "gs://${BUCKET}"
gsutil iam ch "serviceAccount:${SA_EMAIL}:roles/storage.admin" "gs://${TFSTATE_BUCKET}"
echo "    Granted storage.admin on both buckets"

# ── 4. Workload identity pool ─────────────────────────────────────────────────
echo "==> [4/8] Creating workload identity pool..."
if gcloud iam workload-identity-pools describe "$POOL_NAME" \
     --location="global" --project="$PROJECT" &>/dev/null; then
  echo "    Already exists, skipping."
else
  gcloud iam workload-identity-pools create "$POOL_NAME" \
    --location="global" \
    --display-name="GitHub Actions Pool" \
    --project="$PROJECT"
fi

# ── 5. OIDC provider ──────────────────────────────────────────────────────────
echo "==> [5/8] Creating OIDC provider..."
if gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" \
     --location="global" \
     --workload-identity-pool="$POOL_NAME" \
     --project="$PROJECT" &>/dev/null; then
  echo "    Already exists, skipping."
else
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_NAME" \
    --location="global" \
    --workload-identity-pool="$POOL_NAME" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
    --attribute-condition="assertion.repository=='${GITHUB_REPO}'" \
    --project="$PROJECT"
fi

# ── 6. Bind SA to pool ────────────────────────────────────────────────────────
echo "==> [6/8] Binding service account to workload identity pool..."
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/attribute.repository/${GITHUB_REPO}" \
  --project="$PROJECT"

# ── 7. GitHub secrets ─────────────────────────────────────────────────────────
PROVIDER_RESOURCE=$(gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" \
  --location="global" \
  --workload-identity-pool="$POOL_NAME" \
  --project="$PROJECT" \
  --format="value(name)")

echo "==> [7/8] Setting GitHub Actions secrets..."
GH_CLI=$(check_gh_cli)

if [ "$GH_CLI" = "true" ]; then
  echo "    GitHub CLI detected — setting secrets automatically..."
  gh secret set GCP_PROJECT                    --repo="$GITHUB_REPO" --body="$PROJECT"
  gh secret set GCP_SERVICE_ACCOUNT           --repo="$GITHUB_REPO" --body="$SA_EMAIL"
  gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --repo="$GITHUB_REPO" --body="$PROVIDER_RESOURCE"
  gh secret set GCP_BUCKET                    --repo="$GITHUB_REPO" --body="$BUCKET"
  if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
    gh secret set SSH_PUBLIC_KEY --repo="$GITHUB_REPO" --body="$SSH_PUBLIC_KEY"
    echo "    SSH_PUBLIC_KEY set."
  fi
  gh variable set VM_NAME    --repo="$GITHUB_REPO" --body="$VM_NAME"
  gh variable set GCP_REGION --repo="$GITHUB_REPO" --body="$REGION"
  echo "    ✅ All secrets and variables set via GitHub CLI."
else
  echo ""
  echo "    ⚠️  GitHub CLI not found or not authenticated."
  echo "    Add these manually at: https://github.com/${GITHUB_REPO}/settings/secrets/actions"
  echo ""
  echo "    Secrets:"
  echo "      GCP_PROJECT:                    $PROJECT"
  echo "      GCP_SERVICE_ACCOUNT:            $SA_EMAIL"
  echo "      GCP_WORKLOAD_IDENTITY_PROVIDER: $PROVIDER_RESOURCE"
  echo "      GCP_BUCKET:                     $BUCKET"
  [ -n "${SSH_PUBLIC_KEY:-}" ] && echo "      SSH_PUBLIC_KEY:                 $SSH_PUBLIC_KEY"
  echo ""
  echo "    Variables:"
  echo "      VM_NAME:    $VM_NAME"
  echo "      GCP_REGION: $REGION"
fi

# ── 8. Write tfvars ───────────────────────────────────────────────────────────
echo "==> [8/8] Writing terraform/deployments/gcp/terraform.tfvars..."

TFVARS_PATH="$(dirname "$0")/../terraform/deployments/gcp/terraform.tfvars"
mkdir -p "$(dirname "$TFVARS_PATH")"

cat > "$TFVARS_PATH" <<EOF
project        = "$PROJECT"
bucket         = "$BUCKET"
region         = "$REGION"
zone           = "$ZONE"
machine_type   = "$MACHINE_TYPE"
vm_name        = "$VM_NAME"
# image_path and image_hash are set at deploy time by the CI workflow
image_path     = ""
image_hash     = ""
EOF

if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
  echo "ssh_public_key = \"$SSH_PUBLIC_KEY\"" >> "$TFVARS_PATH"
else
  echo "# ssh_public_key = \"ssh-ed25519 AAAA...\"" >> "$TFVARS_PATH"
fi

echo "    Written to $TFVARS_PATH"
echo ""
echo "==> ✅ GCP setup complete."