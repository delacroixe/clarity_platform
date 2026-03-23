#!/usr/bin/env bash
# Build, tag, and push the API Docker image to ECR.
#
# This script is called in two contexts:
#   1. Automatically by Terraform (via terraform_data) on first deploy to seed ECR.
#   2. Manually or by CI/CD to push new application versions.
#
# Tag strategy (applied automatically from Git context):
#   - Git tag (v1.2.3)  → v1.2.3, v1.2, v1, latest, sha-<sha>
#   - main/master branch → latest, sha-<sha>
#   - Other branches     → <sanitised-branch>, sha-<sha>
#   - IMAGE_TAG override → <custom>, sha-<sha>
#
# Environment variables (all optional — sensible defaults provided):
#   AWS_REGION   — Target region          (default: eu-central-1)
#   AWS_PROFILE  — AWS CLI profile        (default: unset / use env creds)
#   ECR_REPO     — Full ECR repo URL      (default: derived from account ID)
#   IMAGE_TAG    — Override primary tag    (default: derived from Git context)
#   SKIP_BUILD   — Set to "1" to skip docker build (push only)
#
# Usage:
#   ./scripts/push_image.sh                       # Build & push (tag from Git)
#   IMAGE_TAG=v1.2.3 ./scripts/push_image.sh      # Build & push :v1.2.3
#   AWS_PROFILE=clarity ./scripts/push_image.sh    # Use named profile

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

AWS_REGION="${AWS_REGION:-eu-central-1}"
SKIP_BUILD="${SKIP_BUILD:-0}"

# ── Resolve image tag from Git context ───────────────────────────────────────
GIT_SHA=$(git -C "$PROJECT_ROOT" rev-parse --short=8 HEAD 2>/dev/null || echo "unknown")
GIT_BRANCH=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
GIT_TAG=$(git -C "$PROJECT_ROOT" describe --tags --exact-match HEAD 2>/dev/null || echo "")

# Determine primary tag with the following priority:
#   1. Explicit IMAGE_TAG env var (CI/CD override)
#   2. Git tag (e.g. v1.2.3) — for production releases
#   3. Branch-based tag (main → latest, feature/foo → feature-foo)
if [[ -n "${IMAGE_TAG:-}" ]]; then
  IMAGE_TAG="$IMAGE_TAG"
elif [[ -n "$GIT_TAG" ]]; then
  IMAGE_TAG="$GIT_TAG"
elif [[ "$GIT_BRANCH" == "main" || "$GIT_BRANCH" == "master" ]]; then
  IMAGE_TAG="latest"
else
  # Sanitise branch name for Docker tag compatibility
  IMAGE_TAG=$(echo "$GIT_BRANCH" | sed 's/[^a-zA-Z0-9._-]/-/g')
fi

echo "==> Image tag strategy:"
echo "    Primary tag : $IMAGE_TAG"
echo "    Git SHA     : $GIT_SHA"
[[ -n "$GIT_TAG" ]] && echo "    Git tag     : $GIT_TAG"
echo "    Git branch  : $GIT_BRANCH"

# Build AWS CLI profile flag (empty when running in CI with env creds)
# Guard against AWS_PROFILE="" (Terraform may pass empty string) — unset it
# so the AWS CLI falls back to env-var / instance-profile credentials.
[[ -z "${AWS_PROFILE:-}" ]] && unset AWS_PROFILE

PROFILE_FLAG=""
if [[ -n "${AWS_PROFILE:-}" ]]; then
  PROFILE_FLAG="--profile $AWS_PROFILE"
fi

# ── Preflight checks ────────────────────────────────────────────────────────
for cmd in aws docker; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' is required but not found in PATH." >&2
    exit 1
  fi
done

# ── Resolve ECR repository URL ──────────────────────────────────────────────
if [[ -z "${ECR_REPO:-}" ]]; then
  ACCOUNT_ID=$(aws sts get-caller-identity $PROFILE_FLAG --query Account --output text)
  ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/clarity-api"
  echo "==> Resolved ECR repo: $ECR_REPO"
fi

# Extract registry URL (everything before the first /)
ECR_REGISTRY="${ECR_REPO%%/*}"

# ── ECR authentication ──────────────────────────────────────────────────────
echo "==> Authenticating with ECR ($ECR_REGISTRY)..."
aws ecr get-login-password --region "$AWS_REGION" $PROFILE_FLAG | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY"

# ── Build ────────────────────────────────────────────────────────────────────
if [[ "$SKIP_BUILD" != "1" ]]; then
  echo "==> Building Docker image (linux/arm64)..."
  docker build \
    --platform linux/arm64 \
    -t clarity-api:build \
    "$PROJECT_ROOT/src"
else
  echo "==> Skipping build (SKIP_BUILD=1)"
fi

# ── Tag ──────────────────────────────────────────────────────────────────────
TAGS=("${IMAGE_TAG}")

# Always add SHA tag for traceability
if [[ "$GIT_SHA" != "unknown" ]]; then
  TAGS+=("sha-${GIT_SHA}")
fi

# If it's a semver git tag (v1.2.3), also push major.minor (v1.2), major (v1) and latest
if [[ "$GIT_TAG" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  MINOR_TAG=$(echo "$GIT_TAG" | grep -oE '^v?[0-9]+\.[0-9]+')
  MAJOR_TAG=$(echo "$GIT_TAG" | grep -oE '^v?[0-9]+')
  TAGS+=("$MINOR_TAG" "$MAJOR_TAG" "latest")
fi

for tag in "${TAGS[@]}"; do
  docker tag clarity-api:build "${ECR_REPO}:${tag}"
  echo "    Tagged ${ECR_REPO}:${tag}"
done

# ── Push ─────────────────────────────────────────────────────────────────────
echo "==> Pushing images to ECR..."
for tag in "${TAGS[@]}"; do
  docker push "${ECR_REPO}:${tag}"
done

echo ""
echo "==> Done! Pushed:"
for tag in "${TAGS[@]}"; do
  echo "    ${ECR_REPO}:${tag}"
done
