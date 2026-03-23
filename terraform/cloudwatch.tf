# --- CloudWatch ---
# Observability: log group with retention, alarms for 5xx errors.

# Lambda log group — created explicitly to control retention
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project_name}-api"
  retention_in_days = 14

  tags = {
    Name = "${var.project_name}-api-logs"
  }
}

# API Gateway log group
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}-api"
  retention_in_days = 14

  tags = {
    Name = "${var.project_name}-api-gateway-logs"
  }
}

# # Alarm: 5xx errors on API Gateway
# resource "aws_cloudwatch_metric_alarm" "api_5xx" {
#   alarm_name          = "${var.project_name}-api-5xx-errors"
#   alarm_description   = "Triggers when API Gateway returns 5xx errors"
#   comparison_operator = "GreaterThanThreshold"
#   evaluation_periods  = 2
#   metric_name         = "5XXError"
#   namespace           = "AWS/ApiGateway"
#   period              = 60
#   statistic           = "Sum"
#   threshold           = 5
#   treat_missing_data  = "notBreaching"

#   dimensions = {
#     ApiName = aws_api_gateway_rest_api.main.name
#     Stage   = aws_api_gateway_stage.v1.stage_name
#   }

#   tags = {
#     Name = "${var.project_name}-api-5xx-alarm"
#   }
# }

# # Alarm: Lambda errors
# resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
#   alarm_name          = "${var.project_name}-lambda-errors"
#   alarm_description   = "Triggers when Lambda function errors exceed threshold"
#   comparison_operator = "GreaterThanThreshold"
#   evaluation_periods  = 2
#   metric_name         = "Errors"
#   namespace           = "AWS/Lambda"
#   period              = 60
#   statistic           = "Sum"
#   threshold           = 3
#   treat_missing_data  = "notBreaching"

#   dimensions = {
#     FunctionName = aws_lambda_function.api.function_name
#   }

#   tags = {
#     Name = "${var.project_name}-lambda-errors-alarm"
#   }
# }

# # Alarm: Lambda duration (detect performance degradation)
# resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
#   alarm_name          = "${var.project_name}-lambda-high-duration"
#   alarm_description   = "Triggers when Lambda p99 latency exceeds 5 seconds"
#   comparison_operator = "GreaterThanThreshold"
#   evaluation_periods  = 3
#   metric_name         = "Duration"
#   namespace           = "AWS/Lambda"
#   period              = 300
#   extended_statistic  = "p99"
#   threshold           = 5000
#   treat_missing_data  = "notBreaching"

#   dimensions = {
#     FunctionName = aws_lambda_function.api.function_name
#   }

#   tags = {
#     Name = "${var.project_name}-lambda-duration-alarm"
#   }
# }

# NOTE: CloudWatch Metric Alarms removed — the candidate permissions boundary
# does not allow cloudwatch:PutMetricAlarm. In production, alarms for 5xx errors,
# Lambda errors, and Lambda duration would be configured here.

