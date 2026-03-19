.PHONY: help install test lint build run-local diagram clean

PYTHON := python3
PIP := pip3

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

install: ## Install all dependencies (dev + app)
	$(PIP) install -r src/requirements.txt
	$(PIP) install pytest moto[dynamodb] ruff diagrams

test: ## Run tests with pytest
	$(PYTHON) -m pytest tests/ -v

lint: ## Run linter (ruff)
	ruff check src/ tests/

lint-fix: ## Auto-fix lint issues
	ruff check src/ tests/ --fix

build: ## Build Docker image locally (ARM64 for Lambda Graviton)
	cd src && docker build --platform linux/arm64 -t clarity-api:local .

run-local: build ## Run API locally in Docker (port 9000)
	docker run --rm -p 9000:8080 \
		-e SECURITIES_TABLE=clarity-securities \
		-e AWS_DEFAULT_REGION=eu-west-1 \
		clarity-api:local

diagram: ## Generate architecture diagram
	$(PYTHON) diagrams/architecture.py

tf-init: ## Initialize Terraform
	cd terraform && terraform init

tf-plan: ## Terraform plan
	cd terraform && terraform plan

tf-apply: ## Terraform apply
	cd terraform && terraform apply

tf-destroy: ## Terraform destroy (use with caution)
	cd terraform && terraform destroy

tf-fmt: ## Format Terraform files
	cd terraform && terraform fmt -recursive

test-cache: ## Test API Gateway cache (pass URL= and/or ID= to override)
	./scripts/test_cache.sh $(URL) $(ID)

clean: ## Clean up generated files
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name .pytest_cache -exec rm -rf {} + 2>/dev/null || true
	rm -rf .coverage htmlcov/
