"""Tests for the Securities API.

Uses moto to mock DynamoDB — no real AWS calls needed.
Tests run locally and in CI without AWS credentials.

Single-table design: one table holds both security metadata and scores.
"""

import os

import boto3
import pytest
from fastapi.testclient import TestClient
from moto import mock_aws

# Set environment variables BEFORE importing app modules
os.environ["SECURITIES_TABLE"] = "clarity-securities"
os.environ["AWS_DEFAULT_REGION"] = "eu-west-1"
os.environ["AWS_ACCESS_KEY_ID"] = "testing"
os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"


MOCK_SECURITIES = ["AAPL", "MSFT", "GOOGL"]

# Single-table: each item contains both metadata and scores
MOCK_ITEMS = {
    "AAPL": {
        "security_id": "AAPL",
        "name": "Apple Inc.",
        "overall_score": "82.5",
        "environmental_score": "78.0",
        "social_score": "85.3",
        "governance_score": "84.1",
        "last_updated": "2026-03-15T10:30:00Z",
    },
    "MSFT": {
        "security_id": "MSFT",
        "name": "Microsoft Corporation",
        "overall_score": "89.2",
        "environmental_score": "91.0",
        "social_score": "87.5",
        "governance_score": "89.0",
        "last_updated": "2026-03-15T10:30:00Z",
    },
    "GOOGL": {
        "security_id": "GOOGL",
        "name": "Alphabet Inc.",
        "overall_score": "76.8",
        "environmental_score": "72.5",
        "social_score": "79.0",
        "governance_score": "78.9",
        "last_updated": "2026-03-15T10:30:00Z",
    },
}


@pytest.fixture
def dynamodb_tables():
    """Create and seed mock DynamoDB table (single-table design)."""
    with mock_aws():
        dynamodb = boto3.resource("dynamodb", region_name="eu-west-1")

        # Single table with both metadata and scores
        table = dynamodb.create_table(
            TableName="clarity-securities",
            KeySchema=[{"AttributeName": "security_id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "security_id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        for item in MOCK_ITEMS.values():
            table.put_item(Item=item)

        # Inject mock DynamoDB resource into the service layer
        from app.services.dynamodb import reset_dynamodb_resource
        reset_dynamodb_resource(dynamodb)

        yield dynamodb

        # Cleanup
        reset_dynamodb_resource(None)


@pytest.fixture
def client(dynamodb_tables):
    """Create FastAPI test client with mocked DynamoDB."""
    from app.main import app
    return TestClient(app)


class TestListSecurities:
    """Tests for GET /securities."""

    def test_returns_200(self, client):
        response = client.get("/securities")
        assert response.status_code == 200

    def test_returns_json(self, client):
        response = client.get("/securities")
        assert response.headers["content-type"] == "application/json"

    def test_returns_securities_list(self, client):
        response = client.get("/securities")
        data = response.json()
        assert "securities" in data
        assert isinstance(data["securities"], list)

    def test_contains_expected_ids(self, client):
        response = client.get("/securities")
        data = response.json()
        for sec_id in MOCK_SECURITIES:
            assert sec_id in data["securities"]

    def test_securities_are_sorted(self, client):
        response = client.get("/securities")
        data = response.json()
        assert data["securities"] == sorted(data["securities"])


class TestGetScores:
    """Tests for GET /securities/{security_id}/scores."""

    def test_known_security_returns_200(self, client):
        response = client.get("/securities/AAPL/scores")
        assert response.status_code == 200

    def test_known_security_returns_json(self, client):
        response = client.get("/securities/AAPL/scores")
        assert response.headers["content-type"] == "application/json"

    def test_response_structure(self, client):
        response = client.get("/securities/AAPL/scores")
        data = response.json()
        assert data["security_id"] == "AAPL"
        assert "scores" in data
        assert "last_updated" in data

    def test_scores_fields(self, client):
        response = client.get("/securities/AAPL/scores")
        scores = response.json()["scores"]
        assert "overall_score" in scores
        assert "environmental_score" in scores
        assert "social_score" in scores
        assert "governance_score" in scores

    def test_scores_are_numeric(self, client):
        response = client.get("/securities/AAPL/scores")
        scores = response.json()["scores"]
        for key, value in scores.items():
            assert isinstance(value, int | float), f"{key} should be numeric"

    def test_scores_in_valid_range(self, client):
        response = client.get("/securities/AAPL/scores")
        scores = response.json()["scores"]
        for key, value in scores.items():
            assert 0 <= value <= 100, f"{key}={value} should be 0-100"

    def test_unknown_security_returns_404(self, client):
        response = client.get("/securities/UNKNOWN/scores")
        assert response.status_code == 404

    def test_404_response_body(self, client):
        response = client.get("/securities/UNKNOWN/scores")
        data = response.json()
        assert "detail" in data
        assert data["detail"] == "Security not found"

    def test_another_known_security(self, client):
        response = client.get("/securities/MSFT/scores")
        assert response.status_code == 200
        data = response.json()
        assert data["security_id"] == "MSFT"


class TestRootEndpoint:
    """Tests for GET / (health check)."""

    def test_root_returns_200(self, client):
        response = client.get("/")
        assert response.status_code == 200

    def test_root_returns_service_info(self, client):
        response = client.get("/")
        data = response.json()
        assert data["status"] == "healthy"
        assert "version" in data
