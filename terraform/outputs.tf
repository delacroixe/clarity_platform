# --- Outputs ---
# Key values exported after terraform apply.

output "api_base_url" {
  description = "Public HTTPS URL of the API"
  value       = aws_api_gateway_stage.v1.invoke_url
}

output "api_securities_url" {
  description = "URL for GET /securities"
  value       = "${aws_api_gateway_stage.v1.invoke_url}/securities"
}

output "ecr_repository_url" {
  description = "ECR repository URL for pushing Docker images"
  value       = aws_ecr_repository.api.repository_url
}

output "lambda_function_name" {
  description = "Lambda function name (used by app CI/CD)"
  value       = aws_lambda_function.api.function_name
}

output "dynamodb_table" {
  description = "DynamoDB Securities table name (single-table design)"
  value       = aws_dynamodb_table.securities.name
}
