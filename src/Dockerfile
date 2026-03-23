# --- Lambda container image ---
# Based on AWS-managed Lambda Python 3.12 base image (ARM64/Graviton).
# ARM64 provides ~20% better price-performance vs x86_64.
FROM public.ecr.aws/lambda/python:3.12-arm64

# Install dependencies first (layer caching optimization)
COPY requirements.txt ${LAMBDA_TASK_ROOT}/
RUN pip install --no-cache-dir -r ${LAMBDA_TASK_ROOT}/requirements.txt

# Copy application code
COPY handler.py ${LAMBDA_TASK_ROOT}/
COPY app/ ${LAMBDA_TASK_ROOT}/app/

# Set the Lambda handler
CMD ["handler.handler"]
