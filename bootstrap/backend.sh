#!/usr/bin/env bash
# Bootstrap script — creates S3 bucket and DynamoDB table for Terraform remote state.
# Run this ONCE before the first `terraform init`.
#
# Usage: ./bootstrap/backend.sh [profile]
# Example: ./bootstrap/backend.sh clarity

set -euo pipefail

PROFILE="${1:-clarity}"
REGION="eu-central-1"
BUCKET="clarity-terraform-state-383941188659"
LOCK_TABLE="clarity-terraform-locks"

echo "==> Creating S3 bucket for Terraform state..."
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION" \
  --profile "$PROFILE" 2>/dev/null || echo "    Bucket already exists, continuing."

echo "==> Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled \
  --profile "$PROFILE"

echo "==> Enabling server-side encryption (AES-256)..."
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }' \
  --profile "$PROFILE"

echo "==> Blocking public access..."
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
  --profile "$PROFILE"

echo "==> Creating DynamoDB table for state locking..."
aws dynamodb create-table \
  --table-name "$LOCK_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION" \
  --profile "$PROFILE" 2>/dev/null || echo "    Lock table already exists, continuing."

echo ""
echo "==> Bootstrap complete!"
echo "    S3 bucket:      $BUCKET"
echo "    Lock table:     $LOCK_TABLE"
echo "    Region:         $REGION"
echo ""
echo "    Now run: cd terraform && terraform init"
