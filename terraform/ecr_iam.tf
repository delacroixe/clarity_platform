# --- ECR Repository ---
# Container registry for Lambda Docker images.
# Image scanning enabled for security vulnerability detection.

resource "aws_ecr_repository" "api" {
  name                 = "${var.project_name}-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-api"
  }
}

# Lifecycle policy: keep only the last 10 images to control storage costs
resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# --- ECR Seed Image ---
# Solves the chicken-and-egg problem: Lambda requires an image in ECR,
# but the ECR repo doesn't exist until Terraform creates it.
# This resource builds and pushes the initial image exactly once,
# after the ECR repo is created. Subsequent image updates are handled
# by CI/CD (Lambda has ignore_changes on image_uri).

resource "terraform_data" "ecr_seed_image" {
  # Re-seed only if the repository is recreated (URL changes)
  input = aws_ecr_repository.api.repository_url

  provisioner "local-exec" {
    command     = "./scripts/push_image.sh"
    working_dir = "${path.module}/.."

    environment = {
      AWS_REGION = var.aws_region
      ECR_REPO   = aws_ecr_repository.api.repository_url
      IMAGE_TAG  = "latest"
    }
  }
}

# --- IAM Role for Lambda ---
# Execution role with least-privilege access.
# This is the "managed identity" — Lambda assumes this role automatically.
# Boto3 picks up temporary STS credentials without any explicit configuration.

resource "aws_iam_role" "lambda_execution" {
  name = "${var.project_name}-lambda-execution-role"

  # CRITICAL: The candidate IAM policy requires a permissions boundary
  # on every role created. Without this, CreateRole will fail with AccessDenied.
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-lambda-execution-role"
  }
}

# DynamoDB read-only access — scoped to the single securities table ARN only
resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "${var.project_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBReadAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query",
        ]
        Resource = [
          aws_dynamodb_table.securities.arn,
        ]
      }
    ]
  })
}

# CloudWatch Logs — required for Lambda to write logs
resource "aws_iam_role_policy" "lambda_logs" {
  name = "${var.project_name}-lambda-logs-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:*"
      }
    ]
  })
}
