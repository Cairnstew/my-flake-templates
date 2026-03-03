#!/usr/bin/env bash
set -euo pipefail

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

aws_region_to_location() {
  # S3 buckets in us-east-1 use a different create-bucket syntax (no LocationConstraint)
  echo "$1"
}
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║     AWS GitHub Actions Setup Script         ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Collect inputs ────────────────────────────────────────────────────────────
prompt GITHUB_REPO   "GitHub repo (e.g. myorg/myrepo)"
prompt BUCKET        "S3 bucket name for NixOS images"

read -rp "AWS region [us-east-1]: " REGION
REGION="${REGION:-us-east-1}"
read -rp "SSH public key for NixOS VM (paste key or leave blank to skip): " SSH_PUBLIC_KEY
read -rp "VM name [myvm]: " VM_NAME
VM_NAME="${VM_NAME:-myvm}"
read -rp "EC2 instance type [t3.small]: " INSTANCE_TYPE
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.small}"

TFSTATE_BUCKET="${BUCKET}-tfstate"
ROLE_NAME="github-actions-nixos"
GITHUB_ORG="${GITHUB_REPO%%/*}"
GITHUB_REPO_NAME="${GITHUB_REPO##*/}"

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo ""
echo "==> Account ID:   $AWS_ACCOUNT_ID"
echo "==> GitHub repo:  $GITHUB_REPO"
echo "==> Image bucket: $BUCKET"
echo "==> State bucket: $TFSTATE_BUCKET"
echo "==> IAM role:     $ROLE_NAME"
echo ""

# ── 1. S3 buckets ─────────────────────────────────────────────────────────────
echo "==> [1/6] Creating S3 buckets..."

create_bucket() {
  local name="$1"
  if aws s3api head-bucket --bucket "$name" 2>/dev/null; then
    echo "    $name already exists, skipping."
  else
    if [ "$REGION" = "us-east-1" ]; then
      aws s3api create-bucket --bucket "$name" --region "$REGION"
    else
      aws s3api create-bucket --bucket "$name" --region "$REGION" \
        --create-bucket-configuration LocationConstraint="$REGION"
    fi
    # Block all public access
    aws s3api put-public-access-block --bucket "$name" \
      --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    # Enable versioning on state bucket for safety
    if [[ "$name" == *tfstate* ]]; then
      aws s3api put-bucket-versioning --bucket "$name" \
        --versioning-configuration Status=Enabled
    fi
    echo "    Created: $name"
  fi
}

create_bucket "$BUCKET"
create_bucket "$TFSTATE_BUCKET"

# ── 2. OIDC provider ──────────────────────────────────────────────────────────
echo "==> [2/6] Setting up GitHub OIDC provider..."

OIDC_URL="https://token.actions.githubusercontent.com"
OIDC_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" &>/dev/null; then
  echo "    OIDC provider already exists, skipping."
else
  # Fetch the thumbprint
  THUMBPRINT=$(echo | openssl s_client -servername token.actions.githubusercontent.com \
    -connect token.actions.githubusercontent.com:443 2>/dev/null \
    | openssl x509 -fingerprint -noout -sha1 \
    | sed 's/.*=//;s/://g' | tr '[:upper:]' '[:lower:]')

  aws iam create-open-id-connect-provider \
    --url "$OIDC_URL" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "$THUMBPRINT"
  echo "    Created OIDC provider."
fi

# ── 3. IAM role ───────────────────────────────────────────────────────────────
echo "==> [3/6] Creating IAM role for GitHub Actions..."

TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_REPO}:*"
        }
      }
    }
  ]
}
EOF
)

if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
  echo "    Role already exists, updating trust policy..."
  aws iam update-assume-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-document "$TRUST_POLICY"
else
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$TRUST_POLICY" \
    --description "GitHub Actions role for NixOS deployments"
  echo "    Created role: $ROLE_NAME"
fi

# ── 4. IAM policy ─────────────────────────────────────────────────────────────
echo "==> [4/6] Attaching IAM permissions..."

POLICY_NAME="github-actions-nixos-policy"
POLICY_DOC=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3Buckets",
      "Effect": "Allow",
      "Action": ["s3:*"],
      "Resource": [
        "arn:aws:s3:::${BUCKET}",
        "arn:aws:s3:::${BUCKET}/*",
        "arn:aws:s3:::${TFSTATE_BUCKET}",
        "arn:aws:s3:::${TFSTATE_BUCKET}/*"
      ]
    },
    {
      "Sid": "EC2andAMI",
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "iam:PassRole",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy",
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:GetInstanceProfile"
      ],
      "Resource": "*"
    }
  ]
}
EOF
)

POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"

if aws iam get-policy --policy-arn "$POLICY_ARN" &>/dev/null; then
  echo "    Policy already exists, updating..."
  VERSION_ID=$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" \
    --query 'Versions[?!IsDefaultVersion].VersionId' --output text | awk '{print $1}')
  [ -n "$VERSION_ID" ] && aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$VERSION_ID"
  aws iam create-policy-version --policy-arn "$POLICY_ARN" \
    --policy-document "$POLICY_DOC" --set-as-default
else
  POLICY_ARN=$(aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document "$POLICY_DOC" \
    --query 'Policy.Arn' --output text)
  echo "    Created policy."
fi

aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN"
echo "    Policy attached."

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"

# ── 5. GitHub secrets ─────────────────────────────────────────────────────────
echo "==> [5/6] Setting GitHub Actions secrets..."
GH_CLI=$(check_gh_cli)

if [ "$GH_CLI" = "true" ]; then
  echo "    GitHub CLI detected — setting secrets automatically..."
  gh secret set AWS_ROLE_ARN  --repo="$GITHUB_REPO" --body="$ROLE_ARN"
  gh secret set AWS_BUCKET    --repo="$GITHUB_REPO" --body="$BUCKET"
  if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
    gh secret set SSH_PUBLIC_KEY --repo="$GITHUB_REPO" --body="$SSH_PUBLIC_KEY"
    echo "    SSH_PUBLIC_KEY set."
  fi
  gh variable set AWS_REGION --repo="$GITHUB_REPO" --body="$REGION"
  gh variable set VM_NAME    --repo="$GITHUB_REPO" --body="$VM_NAME"
  echo "    ✅ All secrets and variables set via GitHub CLI."
else
  echo ""
  echo "    ⚠️  GitHub CLI not found or not authenticated."
  echo "    Add these manually at: https://github.com/${GITHUB_REPO}/settings/secrets/actions"
  echo ""
  echo "    Secrets:"
  echo "      AWS_ROLE_ARN:  $ROLE_ARN"
  echo "      AWS_BUCKET:    $BUCKET"
  [ -n "${SSH_PUBLIC_KEY:-}" ] && echo "      SSH_PUBLIC_KEY: $SSH_PUBLIC_KEY"
  echo ""
  echo "    Variables:"
  echo "      AWS_REGION: $REGION"
  echo "      VM_NAME:    $VM_NAME"
fi

# ── 6. Write tfvars ───────────────────────────────────────────────────────────
echo "==> [6/6] Writing terraform/deployments/aws/terraform.tfvars..."

TFVARS_PATH="$(dirname "$0")/../terraform/deployments/aws/terraform.tfvars"
mkdir -p "$(dirname "$TFVARS_PATH")"

cat > "$TFVARS_PATH" <<EOF
bucket        = "$BUCKET"
region        = "$REGION"
instance_type = "$INSTANCE_TYPE"
vm_name       = "$VM_NAME"
# image_path and image_hash are set at deploy time by the CI workflow
image_path    = ""
image_hash    = ""
EOF

if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
  echo "ssh_public_key = \"$SSH_PUBLIC_KEY\"" >> "$TFVARS_PATH"
else
  echo "# ssh_public_key = \"ssh-ed25519 AAAA...\"" >> "$TFVARS_PATH"
fi

echo "    Written to $TFVARS_PATH"
echo ""
echo "==> ✅ AWS setup complete."
echo ""
echo "    Role ARN:     $ROLE_ARN"
echo "    State bucket: s3://$TFSTATE_BUCKET"
echo ""
echo "    Run 'cd terraform/deployments/aws && tofu init' to initialise the backend."