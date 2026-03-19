variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-west-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use (set to null in CI/CD where env vars are used)"
  type        = string
  default     = null
}

variable "project_name" {
  description = "Project name used as prefix for all resources"
  type        = string
  default     = "clarity"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

variable "lambda_memory_size" {
  description = "Lambda function memory in MB"
  type        = number
  default     = 256
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 10
}

variable "api_cache_ttl" {
  description = "API Gateway cache TTL in seconds"
  type        = number
  default     = 300
}

variable "waf_rate_limit" {
  description = "WAF rate limit: max requests per 5-minute window per IP"
  type        = number
  default     = 1000
}

variable "permissions_boundary_arn" {
  description = "IAM permissions boundary ARN required by the candidate policy. All roles must include this."
  type        = string
  default     = "arn:aws:iam::383941188659:policy/candidate"
}
