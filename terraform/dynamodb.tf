# --- DynamoDB Table (Single-Table Design) ---
# Single table holds both security metadata and scores.
# This is the canonical DynamoDB pattern — one table per service.
# With only 2 access patterns (list IDs, get scores by ID),
# a single table with PK=security_id is optimal.
#
# On-demand billing: zero cost at rest, pay only per request.

resource "aws_dynamodb_table" "securities" {
  name         = "${var.project_name}-securities"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "security_id"

  attribute {
    name = "security_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-securities"
  }
}

# --- Seed Data ---
# Mock data loaded directly via Terraform for demo purposes.
# In production, this would be populated by an ingestion pipeline.
# Each item contains both the security metadata and its scores.

locals {
  securities_seed = {
    "AAPL" = {
      name                = "Apple Inc."
      overall_score       = 82.5
      environmental_score = 78.0
      social_score        = 85.3
      governance_score    = 84.1
      last_updated        = "2026-03-15T10:30:00Z"
    }
    "MSFT" = {
      name                = "Microsoft Corporation"
      overall_score       = 89.2
      environmental_score = 91.0
      social_score        = 87.5
      governance_score    = 89.0
      last_updated        = "2026-03-15T10:30:00Z"
    }
    "GOOGL" = {
      name                = "Alphabet Inc."
      overall_score       = 76.8
      environmental_score = 72.5
      social_score        = 79.0
      governance_score    = 78.9
      last_updated        = "2026-03-15T10:30:00Z"
    }
    "TSLA" = {
      name                = "Tesla Inc."
      overall_score       = 68.4
      environmental_score = 85.0
      social_score        = 52.3
      governance_score    = 67.8
      last_updated        = "2026-03-15T10:30:00Z"
    }
    "AMZN" = {
      name                = "Amazon.com Inc."
      overall_score       = 74.1
      environmental_score = 65.2
      social_score        = 78.5
      governance_score    = 78.6
      last_updated        = "2026-03-15T10:30:00Z"
    }
    "META" = {
      name                = "Meta Platforms Inc."
      overall_score       = 71.3
      environmental_score = 69.0
      social_score        = 65.8
      governance_score    = 79.0
      last_updated        = "2026-03-15T10:30:00Z"
    }
    "NVDA" = {
      name                = "NVIDIA Corporation"
      overall_score       = 80.7
      environmental_score = 75.5
      social_score        = 82.0
      governance_score    = 84.5
      last_updated        = "2026-03-15T10:30:00Z"
    }
    "JPM" = {
      name                = "JPMorgan Chase & Co."
      overall_score       = 77.9
      environmental_score = 70.0
      social_score        = 80.5
      governance_score    = 83.2
      last_updated        = "2026-03-15T10:30:00Z"
    }
  }
}

resource "aws_dynamodb_table_item" "securities" {
  for_each   = local.securities_seed
  table_name = aws_dynamodb_table.securities.name
  hash_key   = aws_dynamodb_table.securities.hash_key

  item = jsonencode({
    security_id         = { S = each.key }
    name                = { S = each.value.name }
    overall_score       = { N = tostring(each.value.overall_score) }
    environmental_score = { N = tostring(each.value.environmental_score) }
    social_score        = { N = tostring(each.value.social_score) }
    governance_score    = { N = tostring(each.value.governance_score) }
    last_updated        = { S = each.value.last_updated }
  })

  lifecycle {
    ignore_changes = [item]
  }
}
