"""AWS Lambda handler — Mangum adapter for FastAPI.

Mangum translates API Gateway events into ASGI requests
that FastAPI can process, and converts the responses back
to API Gateway format.
"""

from mangum import Mangum

from app.main import app

handler = Mangum(app, lifespan="off")
