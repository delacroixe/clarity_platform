"""DynamoDB service layer (single-table design).

Uses IAM Execution Role for authentication — no credentials in code.
Boto3 automatically picks up temporary credentials from the Lambda
execution environment via STS AssumeRole.

Single-table design: all data lives in one table with PK=security_id.
Each item contains both metadata (name) and scores.
"""

import os
from typing import Any

import boto3

# Single table — injected via Lambda environment variable (set by Terraform)
SECURITIES_TABLE = os.environ.get("SECURITIES_TABLE", "clarity-securities")

# Initialize DynamoDB resource — uses IAM role credentials automatically
_dynamodb = None


def _get_dynamodb_resource():
    """Lazy initialization of DynamoDB resource for testability."""
    global _dynamodb
    if _dynamodb is None:
        _dynamodb = boto3.resource("dynamodb")
    return _dynamodb


def reset_dynamodb_resource(resource=None):
    """Reset DynamoDB resource — used in tests to inject mocks."""
    global _dynamodb
    _dynamodb = resource


def get_all_securities() -> list[str]:
    """Retrieve all security IDs from the table.

    Uses a scan with ProjectionExpression to minimize read cost.
    Handles pagination for datasets exceeding 1MB per scan.

    Returns:
        Sorted list of security_id strings.
    """
    dynamodb = _get_dynamodb_resource()
    table = dynamodb.Table(SECURITIES_TABLE)
    response = table.scan(
        ProjectionExpression="security_id",
    )

    securities = [item["security_id"] for item in response.get("Items", [])]

    # Handle pagination for large datasets
    while "LastEvaluatedKey" in response:
        response = table.scan(
            ProjectionExpression="security_id",
            ExclusiveStartKey=response["LastEvaluatedKey"],
        )
        securities.extend(
            item["security_id"] for item in response.get("Items", [])
        )

    return sorted(securities)


def get_security_scores(security_id: str) -> dict[str, Any] | None:
    """Retrieve scores for a specific security (single-table: same table, same item).

    Args:
        security_id: The security identifier (e.g., "AAPL").

    Returns:
        Dictionary with score data, or None if security not found.
    """
    dynamodb = _get_dynamodb_resource()
    table = dynamodb.Table(SECURITIES_TABLE)
    response = table.get_item(
        Key={"security_id": security_id},
    )

    return response.get("Item")
