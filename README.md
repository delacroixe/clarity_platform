# Clarity Platform — Securities Scores API

Public REST API serving refined scores for financial securities, designed for third-party consumption worldwide.

## Architecture

```
Client (HTTPS) → WAF (rate limit) → API Gateway (REST + cache) → Lambda (Docker/ECR) → DynamoDB
                                                                         ↑
                                                                   IAM Execution Role
                                                                   (zero credentials)
```

> Full diagram: see `diagrams/` directory. Generate with `make diagram`.

## Tech Stack

| Component       | Technology                            | Rationale                                         |
|-----------------|---------------------------------------|---------------------------------------------------|
| **API**         | Python 3.12 + FastAPI + Mangum        | Modern, typed, auto-docs (Swagger), fast dev       |
| **Compute**     | AWS Lambda (container image)          | Serverless, pay-per-use, zero ops overhead         |
| **Registry**    | Amazon ECR                            | Image scanning, lifecycle policies, native to AWS  |
| **Database**    | DynamoDB (on-demand)                  | Serverless, zero cost at rest, ms latency          |
| **API Layer**   | API Gateway (REST) + cache            | HTTPS built-in, caching, throttling                |
| **Security**    | WAF v2 + IAM Execution Role           | Rate-limiting + least-privilege (zero secrets)     |
| **IaC**         | Terraform                             | Industry standard, declarative, state management   |
| **CI/CD**       | GitHub Actions (2 independent workflows) | Path-based triggers, infra/app separation       |
| **Observability** | CloudWatch (logs, metrics, alarms)  | Native, zero config, retention policies            |

## API Endpoints

| Method | Path                              | Description                    | Response  |
|--------|-----------------------------------|--------------------------------|-----------|
| GET    | `/securities`                     | List all security IDs          | 200 + JSON |
| GET    | `/securities/{security_id}/scores`| Get scores for a security      | 200 / 404  |
| GET    | `/`                               | Health check                   | 200        |
| GET    | `/docs`                           | Swagger UI (auto-generated)    | 200        |

### Example responses

```bash
# List securities
curl https://<api-url>/v1/securities
```
```json
{
  "securities": ["AAPL", "AMZN", "GOOGL", "JPM", "META", "MSFT", "NVDA", "TSLA"]
}
```

```bash
# Get scores
curl https://<api-url>/v1/securities/AAPL/scores
```
```json
{
  "security_id": "AAPL",
  "scores": {
    "overall_score": 82.5,
    "environmental_score": 78.0,
    "social_score": 85.3,
    "governance_score": 84.1
  },
  "last_updated": "2026-03-15T10:30:00Z"
}
```

```bash
# Unknown security → 404
curl https://<api-url>/v1/securities/UNKNOWN/scores
```
```json
{
  "detail": "Security not found"
}
```

## Project Structure

```
clarity_platform/
├── terraform/              # Infrastructure as Code (Terraform)
│   ├── providers.tf        # AWS provider + backend config
│   ├── variables.tf        # Input variables
│   ├── outputs.tf          # Exported values
│   ├── dynamodb.tf         # DynamoDB tables + seed data
│   ├── ecr_iam.tf          # ECR repository + IAM execution role
│   ├── api.tf              # Lambda + API Gateway
│   ├── waf.tf              # WAF v2 rate limiting
│   └── cloudwatch.tf       # Log groups + alarms
├── src/                    # Application code
│   ├── Dockerfile          # Lambda container image
│   ├── handler.py          # Lambda entry point (Mangum)
│   ├── requirements.txt    # Python dependencies
│   └── app/
│       ├── main.py         # FastAPI application
│       ├── routes/         # API endpoints
│       ├── models/         # Pydantic schemas
│       └── services/       # DynamoDB service layer
├── tests/                  # Pytest + moto tests
├── .github/workflows/
│   ├── infra.yml           # Terraform CI/CD (path: terraform/**)
│   └── app.yml             # App CI/CD (path: src/**)
├── diagrams/               # Architecture diagram (as code)
├── Makefile                # Dev commands
└── pyproject.toml          # Python tooling config
```

## CI/CD — Two Independent Workflows

### `infra.yml` — Infrastructure (triggers on `terraform/**`)

```
terraform fmt → terraform validate → terraform plan → terraform apply (main only)
```

### `app.yml` — Application (triggers on `src/**`)

```
ruff lint → pytest → docker build → push ECR → update Lambda → smoke tests
```

This separation means:
- Infra changes don't rebuild the app
- App changes don't touch infrastructure
- Each workflow can be reviewed and deployed independently

## Architecture Decisions

### Why Lambda + API Gateway (not ECS/EKS)?
- **Cost**: $0 at rest, pay only per request. For a scores API with cacheable data, this is optimal.
- **Ops overhead**: Zero. No clusters, no scaling policies, no health checks to configure.
- **Right-sizing**: The challenge specifies a simple API with mock data. EKS/ECS would be over-engineering.

### Why container image (not zip)?
- **Reproducibility**: Same image runs locally and in Lambda. No "works on my machine".
- **Dependency management**: Native libs install cleanly in Docker. No Lambda layer complexity.
- **CI/CD clarity**: Build → push → update. Standard container workflow.
- **Security scanning**: ECR scans images on push for known CVEs.

### Why IAM Execution Role (not Secrets Manager)?
- DynamoDB authentication is IAM-native. No username/password exists.
- The Lambda's execution role grants precisely scoped permissions (`GetItem`, `Scan` on specific table ARNs).
- Zero secrets to rotate, zero credentials in code or environment variables.
- This is AWS's equivalent of "managed identities" — the compute has its own identity.

### Why API Gateway caching (not ElastiCache)?
- Coherent with the serverless architecture — no additional infrastructure to manage.
- Sufficient for this use case: scores update periodically, not in real-time.
- 300s TTL balances freshness with performance.
- Can be upgraded to ElastiCache if data patterns require it.

### Why WAF?
- Not required by the challenge, but demonstrates security-first thinking.
- Rate-limiting protects against abuse on a public API.
- AWS Managed Rules block common attack patterns (SQLi, XSS).
- Minimal cost, significant protection.

## Local Development

```bash
# Install dependencies
make install

# Run tests
make test

# Lint
make lint

# Build Docker image locally
make build

# Generate architecture diagram
make diagram
```

## Deployment

### Prerequisites

1. AWS account with appropriate permissions
2. GitHub repository secrets configured:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
3. GitHub repository variable:
   - `AWS_REGION` (default: `eu-west-1`)

### First-time setup

```bash
# 1. Initialize Terraform
make tf-init

# 2. Deploy infrastructure (creates ECR, DynamoDB, API Gateway, Lambda placeholder)
make tf-apply

# 3. Build and push the first Docker image
cd src
ECR_URL=$(cd ../terraform && terraform output -raw ecr_repository_url)
docker build -t $ECR_URL:latest .
aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_URL
docker push $ECR_URL:latest

# 4. Update Lambda to use the image
FUNC_NAME=$(cd ../terraform && terraform output -raw lambda_function_name)
aws lambda update-function-code --function-name $FUNC_NAME --image-uri $ECR_URL:latest

# 5. Verify
API_URL=$(cd ../terraform && terraform output -raw api_base_url)
curl $API_URL/securities
```

After initial setup, all deployments are automated via GitHub Actions.

## GitHub Secrets Required

| Secret                   | Description                      |
|--------------------------|----------------------------------|
| `AWS_ACCESS_KEY_ID`      | IAM user access key for CI/CD    |
| `AWS_SECRET_ACCESS_KEY`  | IAM user secret key for CI/CD    |

| Variable      | Description             | Default      |
|---------------|-------------------------|--------------|
| `AWS_REGION`  | Target AWS region       | `eu-west-1`  |
