"""Securities API routes."""

import logging

from fastapi import APIRouter, HTTPException, Request

from app.models.schemas import (
    ErrorResponse,
    ScoreDetail,
    SecuritiesResponse,
    SecurityScoresResponse,
)
from app.services.dynamodb import get_all_securities, get_security_scores

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/securities", tags=["Securities"])


@router.get(
    "",
    response_model=SecuritiesResponse,
    summary="List all security IDs",
    description="Returns a list of all available security identifiers.",
)
async def list_securities() -> SecuritiesResponse:
    """GET /securities — returns all available security IDs."""
    securities = get_all_securities()
    return SecuritiesResponse(securities=securities)


@router.get(
    "/{security_id}/scores",
    response_model=SecurityScoresResponse,
    summary="Get scores for a security",
    description="Returns the computed score details for a given security ID.",
    responses={
        404: {
            "model": ErrorResponse,
            "description": "Security not found",
        },
    },
)
async def get_scores(security_id: str, request: Request) -> SecurityScoresResponse:
    """GET /securities/{security_id}/scores — returns scores or 404."""
    req_id = request.headers.get("x-amzn-requestid", "local")
    logger.info("LAMBDA_INVOKED path=/securities/%s/scores request_id=%s", security_id, req_id)
    item = get_security_scores(security_id)

    if item is None:
        raise HTTPException(status_code=404, detail="Security not found")

    scores = ScoreDetail(
        overall_score=float(item["overall_score"]),
        environmental_score=float(item["environmental_score"]),
        social_score=float(item["social_score"]),
        governance_score=float(item["governance_score"]),
    )

    return SecurityScoresResponse(
        security_id=item["security_id"],
        scores=scores,
        last_updated=item["last_updated"],
    )
