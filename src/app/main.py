"""Clarity Platform — Securities Scores API.

FastAPI application exposing refined scores for financial securities.
Designed to run on AWS Lambda behind API Gateway.
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routes.securities import router as securities_router

app = FastAPI(
    title="Clarity Platform API",
    description=(
        "Public REST API serving refined scores for financial securities. "
        "Consumed by third parties worldwide."
    ),
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# CORS — intentionally open to all origins.
# This is a public API designed for third-party consumption worldwide.
# Restricting origins would break legitimate integrations since consumers
# may call from any domain (browser-based dashboards, etc.).
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)

# Register routes
app.include_router(securities_router)


@app.get("/", include_in_schema=False)
async def root():
    """Health check / root endpoint."""
    return {"service": "clarity-platform", "status": "healthy", "version": "1.0.0"}
