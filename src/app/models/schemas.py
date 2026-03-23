"""Pydantic models for API request/response validation."""


from pydantic import BaseModel, Field


class SecurityItem(BaseModel):
    """Single security identifier."""

    security_id: str = Field(..., examples=["AAPL"])


class SecuritiesResponse(BaseModel):
    """Response model for GET /securities."""

    securities: list[str] = Field(
        ...,
        description="List of available security identifiers",
        examples=[["AAPL", "MSFT", "GOOGL", "TSLA", "AMZN"]],
    )


class ScoreDetail(BaseModel):
    """Score breakdown for a single security."""

    overall_score: float = Field(..., ge=0, le=100, examples=[82.5])
    environmental_score: float = Field(..., ge=0, le=100, examples=[78.0])
    social_score: float = Field(..., ge=0, le=100, examples=[85.3])
    governance_score: float = Field(..., ge=0, le=100, examples=[84.1])


class SecurityScoresResponse(BaseModel):
    """Response model for GET /securities/{security_id}/scores."""

    security_id: str = Field(..., examples=["AAPL"])
    scores: ScoreDetail
    last_updated: str = Field(
        ...,
        description="ISO 8601 timestamp of last score computation",
        examples=["2026-03-15T10:30:00Z"],
    )


class ErrorResponse(BaseModel):
    """Standard error response."""

    detail: str = Field(..., examples=["Security not found"])
