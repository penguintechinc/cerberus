# Cerberus NGFW Makefile
# Development tasks for Flask + Go + React microservices

.PHONY: help setup dev test build clean lint format docker deploy smoke-test test-e2e seed-mock-data

# Default target
.DEFAULT_GOAL := help

# Variables
PROJECT_NAME := cerberus
VERSION := $(shell cat .version 2>/dev/null || echo "development")
DOCKER_REGISTRY := ghcr.io
DOCKER_ORG := penguintechinc
GO_VERSION := 1.24
PYTHON_VERSION := 3.13
NODE_VERSION := 22

# Service paths
FLASK_DIR := services/flask-backend
GO_DIR := services/go-backend
WEBUI_DIR := services/webui

# Colors for output
RED := \033[31m
GREEN := \033[32m
YELLOW := \033[33m
BLUE := \033[34m
RESET := \033[0m

# Help target
help: ## Show this help message
	@echo "$(BLUE)$(PROJECT_NAME) Development Commands$(RESET)"
	@echo ""
	@echo "$(GREEN)Setup Commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / && /Setup/ {printf "  $(YELLOW)%-20s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(GREEN)Development Commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / && /Development/ {printf "  $(YELLOW)%-20s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(GREEN)Testing Commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / && /Testing/ {printf "  $(YELLOW)%-20s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(GREEN)Build Commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / && /Build/ {printf "  $(YELLOW)%-20s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(GREEN)Docker Commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / && /Docker/ {printf "  $(YELLOW)%-20s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(GREEN)Other Commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / && !/Setup|Development|Testing|Build|Docker/ {printf "  $(YELLOW)%-20s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Setup Commands
setup: ## Setup - Install all dependencies and initialize the project
	@echo "$(BLUE)Setting up $(PROJECT_NAME)...$(RESET)"
	@$(MAKE) setup-env
	@$(MAKE) setup-go
	@$(MAKE) setup-python
	@$(MAKE) setup-node
	@echo "$(GREEN)Setup complete!$(RESET)"

setup-env: ## Setup - Create environment file from template
	@if [ ! -f .env ]; then \
		if [ -f .env.example ]; then \
			echo "$(YELLOW)Creating .env from .env.example...$(RESET)"; \
			cp .env.example .env; \
		else \
			echo "$(YELLOW)No .env.example found, skipping...$(RESET)"; \
		fi; \
	fi

setup-go: ## Setup - Install Go dependencies and tools
	@echo "$(BLUE)Setting up Go dependencies...$(RESET)"
	@go version || (echo "$(RED)Go $(GO_VERSION) not installed$(RESET)" && exit 1)
	@cd $(GO_DIR) && go mod download && go mod tidy
	@go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest

setup-python: ## Setup - Install Python dependencies and tools
	@echo "$(BLUE)Setting up Python dependencies...$(RESET)"
	@python3 --version || (echo "$(RED)Python $(PYTHON_VERSION) not installed$(RESET)" && exit 1)
	@pip install --upgrade pip
	@pip install -r $(FLASK_DIR)/requirements.txt

setup-node: ## Setup - Install Node.js dependencies and tools
	@echo "$(BLUE)Setting up Node.js dependencies...$(RESET)"
	@node --version || (echo "$(RED)Node.js $(NODE_VERSION) not installed$(RESET)" && exit 1)
	@cd $(WEBUI_DIR) && npm install

# Development Commands
dev: ## Development - Start development environment
	@echo "$(BLUE)Starting development environment...$(RESET)"
	@docker-compose up -d postgres redis
	@sleep 5
	@$(MAKE) dev-services

dev-services: ## Development - Start all services for development
	@echo "$(BLUE)Starting development services...$(RESET)"
	@trap 'docker-compose down' INT; \
	concurrently --names "Flask,Go,WebUI" --prefix name --kill-others \
		"$(MAKE) dev-flask" \
		"$(MAKE) dev-go" \
		"$(MAKE) dev-webui"

dev-flask: ## Development - Start Flask backend in development mode
	@echo "$(BLUE)Starting Flask backend...$(RESET)"
	@cd $(FLASK_DIR) && FLASK_DEBUG=true python run.py

dev-go: ## Development - Start Go backend in development mode
	@echo "$(BLUE)Starting Go backend...$(RESET)"
	@cd $(GO_DIR) && go run ./cmd/server

dev-webui: ## Development - Start WebUI in development mode
	@echo "$(BLUE)Starting WebUI...$(RESET)"
	@cd $(WEBUI_DIR) && npm run dev

dev-db: ## Development - Start only database services
	@docker-compose up -d postgres redis

dev-monitoring: ## Development - Start monitoring services
	@docker-compose up -d prometheus grafana

dev-full: ## Development - Start full development stack
	@docker-compose up -d

# Testing Commands
test: ## Testing - Run all tests
	@echo "$(BLUE)Running all tests...$(RESET)"
	@$(MAKE) test-python
	@$(MAKE) test-go
	@$(MAKE) test-node
	@echo "$(GREEN)All tests completed!$(RESET)"

test-go: ## Testing - Run Go tests
	@echo "$(BLUE)Running Go tests...$(RESET)"
	@cd $(GO_DIR) && go test -v -race -coverprofile=coverage-go.out ./...

test-python: ## Testing - Run Python tests
	@echo "$(BLUE)Running Python tests...$(RESET)"
	@pytest tests/ --cov=$(FLASK_DIR)/app --cov-report=xml:coverage-python.xml --cov-report=html:htmlcov-python -v

test-node: ## Testing - Run Node.js tests
	@echo "$(BLUE)Running Node.js tests...$(RESET)"
	@cd $(WEBUI_DIR) && npm run typecheck

test-integration: ## Testing - Run integration tests
	@echo "$(BLUE)Running integration tests...$(RESET)"
	@RUN_INTEGRATION_TESTS=true pytest tests/integration/ -v

test-coverage: ## Testing - Generate coverage reports
	@$(MAKE) test
	@echo "$(GREEN)Coverage reports generated:$(RESET)"
	@echo "  Go: $(GO_DIR)/coverage-go.out"
	@echo "  Python: coverage-python.xml, htmlcov-python/"

smoke-test: ## Testing - Run smoke tests (build, health, API, pages)
	@echo "$(BLUE)Running smoke tests...$(RESET)"
	@bash tests/smoke/test_build.sh
	@bash tests/smoke/test_health.sh
	@bash tests/smoke/test_api.sh
	@bash tests/smoke/test_pages.sh
	@echo "$(GREEN)Smoke tests completed!$(RESET)"

test-e2e: ## Testing - Run Playwright end-to-end tests
	@echo "$(BLUE)Running Playwright E2E tests...$(RESET)"
	@npx playwright test
	@echo "$(GREEN)E2E tests completed!$(RESET)"

seed-mock-data: ## Testing - Seed mock data for development
	@echo "$(BLUE)Seeding mock data...$(RESET)"
	@python3 scripts/seed-mock-data.py

# Build Commands
build: ## Build - Build all applications
	@echo "$(BLUE)Building all applications...$(RESET)"
	@$(MAKE) build-go
	@$(MAKE) build-python
	@$(MAKE) build-node
	@echo "$(GREEN)All builds completed!$(RESET)"

build-go: ## Build - Build Go applications
	@echo "$(BLUE)Building Go applications...$(RESET)"
	@mkdir -p bin
	@cd $(GO_DIR) && CGO_ENABLED=1 go build -ldflags "-X main.version=$(VERSION)" -o ../../bin/cerberus-xdp ./cmd/server

build-python: ## Build - Verify Python applications compile
	@echo "$(BLUE)Checking Python applications...$(RESET)"
	@python3 -m py_compile $(FLASK_DIR)/run.py
	@python3 -m py_compile $(FLASK_DIR)/app/__init__.py

build-node: ## Build - Build Node.js applications
	@echo "$(BLUE)Building Node.js applications...$(RESET)"
	@cd $(WEBUI_DIR) && npm run build

build-production: ## Build - Build for production with optimizations
	@echo "$(BLUE)Building for production...$(RESET)"
	@cd $(GO_DIR) && CGO_ENABLED=1 GOOS=linux go build -ldflags "-w -s -X main.version=$(VERSION)" -o ../../bin/cerberus-xdp ./cmd/server
	@cd $(WEBUI_DIR) && npm run build

# Docker Commands
docker-build: ## Docker - Build all Docker images
	@echo "$(BLUE)Building Docker images...$(RESET)"
	@docker build -t $(DOCKER_REGISTRY)/$(DOCKER_ORG)/$(PROJECT_NAME)-api:$(VERSION) $(FLASK_DIR)/
	@docker build -t $(DOCKER_REGISTRY)/$(DOCKER_ORG)/$(PROJECT_NAME)-xdp:$(VERSION) $(GO_DIR)/
	@docker build -t $(DOCKER_REGISTRY)/$(DOCKER_ORG)/$(PROJECT_NAME)-webui:$(VERSION) $(WEBUI_DIR)/

docker-push: ## Docker - Push Docker images to registry
	@echo "$(BLUE)Pushing Docker images...$(RESET)"
	@docker push $(DOCKER_REGISTRY)/$(DOCKER_ORG)/$(PROJECT_NAME)-api:$(VERSION)
	@docker push $(DOCKER_REGISTRY)/$(DOCKER_ORG)/$(PROJECT_NAME)-xdp:$(VERSION)
	@docker push $(DOCKER_REGISTRY)/$(DOCKER_ORG)/$(PROJECT_NAME)-webui:$(VERSION)

docker-run: ## Docker - Run application with Docker Compose
	@docker-compose up --build

docker-clean: ## Docker - Clean up Docker resources
	@echo "$(BLUE)Cleaning up Docker resources...$(RESET)"
	@docker-compose down -v
	@docker system prune -f

# Code Quality Commands
lint: ## Code Quality - Run linting for all languages
	@echo "$(BLUE)Running linting...$(RESET)"
	@$(MAKE) lint-go
	@$(MAKE) lint-python
	@$(MAKE) lint-node

lint-go: ## Code Quality - Run Go linting
	@echo "$(BLUE)Linting Go code...$(RESET)"
	@cd $(GO_DIR) && golangci-lint run ./...

lint-python: ## Code Quality - Run Python linting
	@echo "$(BLUE)Linting Python code...$(RESET)"
	@cd $(FLASK_DIR) && flake8 app/ --max-line-length=100
	@cd $(FLASK_DIR) && mypy app/ --ignore-missing-imports

lint-node: ## Code Quality - Run Node.js linting
	@echo "$(BLUE)Linting Node.js code...$(RESET)"
	@cd $(WEBUI_DIR) && npm run lint

format: ## Code Quality - Format code for all languages
	@echo "$(BLUE)Formatting code...$(RESET)"
	@$(MAKE) format-go
	@$(MAKE) format-python
	@$(MAKE) format-node

format-go: ## Code Quality - Format Go code
	@echo "$(BLUE)Formatting Go code...$(RESET)"
	@cd $(GO_DIR) && go fmt ./...

format-python: ## Code Quality - Format Python code
	@echo "$(BLUE)Formatting Python code...$(RESET)"
	@cd $(FLASK_DIR) && black app/ --line-length=100
	@cd $(FLASK_DIR) && isort app/

format-node: ## Code Quality - Format Node.js code
	@echo "$(BLUE)Formatting Node.js code...$(RESET)"
	@cd $(WEBUI_DIR) && npm run lint:fix

# Database Commands
db-migrate: ## Database - Run database migrations (PyDAL auto-migrates)
	@echo "$(BLUE)PyDAL handles migrations automatically on startup$(RESET)"

db-seed: ## Database - Seed database with mock data
	@$(MAKE) seed-mock-data

db-reset: ## Database - Reset database (WARNING: destroys data)
	@echo "$(RED)WARNING: This will destroy all data!$(RESET)"
	@read -p "Are you sure? (y/N): " confirm && [ "$$confirm" = "y" ]
	@docker-compose down -v
	@docker-compose up -d postgres redis
	@sleep 5
	@echo "$(GREEN)Database reset complete. Start Flask to re-initialize.$(RESET)"

db-backup: ## Database - Create database backup
	@echo "$(BLUE)Creating database backup...$(RESET)"
	@mkdir -p backups
	@docker-compose exec postgres pg_dump -U cerberus cerberus_db > backups/backup-$(shell date +%Y%m%d-%H%M%S).sql

db-restore: ## Database - Restore database from backup (requires BACKUP_FILE)
	@echo "$(BLUE)Restoring database from $(BACKUP_FILE)...$(RESET)"
	@docker-compose exec -T postgres psql -U cerberus cerberus_db < $(BACKUP_FILE)

# License Commands
license-validate: ## License - Validate license configuration
	@echo "$(BLUE)Validating license configuration...$(RESET)"
	@python3 -c "from services.flask_backend.app.licensing import validate_license; print(validate_license())" 2>/dev/null || echo "License validation requires running Flask backend"

license-test: ## License - Test license server integration
	@echo "$(BLUE)Testing license server integration...$(RESET)"
	@curl -f $${LICENSE_SERVER_URL:-https://license.penguintech.io}/api/v2/validate \
		-H "Authorization: Bearer $${LICENSE_KEY}" \
		-H "Content-Type: application/json" \
		-d '{"product": "'$${PRODUCT_NAME:-cerberus}'"}'

# Version Management Commands
version-update: ## Version - Update version (patch by default)
	@./scripts/version/update-version.sh

version-update-minor: ## Version - Update minor version
	@./scripts/version/update-version.sh minor

version-update-major: ## Version - Update major version
	@./scripts/version/update-version.sh major

version-show: ## Version - Show current version
	@echo "Current version: $(VERSION)"

# Deployment Commands
deploy-staging: ## Deploy - Deploy to staging environment
	@echo "$(BLUE)Deploying to staging...$(RESET)"
	@$(MAKE) docker-build
	@$(MAKE) docker-push

deploy-production: ## Deploy - Deploy to production environment
	@echo "$(BLUE)Deploying to production...$(RESET)"
	@$(MAKE) docker-build
	@$(MAKE) docker-push

# Health Check Commands
health: ## Health - Check service health
	@echo "$(BLUE)Checking service health...$(RESET)"
	@curl -sf http://localhost:5000/healthz && echo "$(GREEN)Flask API: healthy$(RESET)" || echo "$(RED)Flask API: unreachable$(RESET)"
	@curl -sf http://localhost:8080/healthz && echo "$(GREEN)Go XDP: healthy$(RESET)" || echo "$(RED)Go XDP: unreachable$(RESET)"
	@curl -sf http://localhost:3000/healthz && echo "$(GREEN)WebUI: healthy$(RESET)" || echo "$(RED)WebUI: unreachable$(RESET)"

logs: ## Logs - Show service logs
	@docker-compose logs -f

logs-api: ## Logs - Show Flask API logs
	@docker-compose logs -f cerberus-api

logs-xdp: ## Logs - Show Go XDP logs
	@docker-compose logs -f cerberus-xdp

logs-webui: ## Logs - Show WebUI logs
	@docker-compose logs -f cerberus-webui

logs-db: ## Logs - Show database logs
	@docker-compose logs -f postgres redis

# Cleanup Commands
clean: ## Clean - Clean build artifacts and caches
	@echo "$(BLUE)Cleaning build artifacts...$(RESET)"
	@rm -rf bin/
	@rm -rf dist/
	@rm -rf $(WEBUI_DIR)/node_modules/
	@rm -rf $(WEBUI_DIR)/dist/
	@rm -rf __pycache__/
	@rm -rf .pytest_cache/
	@rm -rf htmlcov-python/
	@rm -rf coverage-*.out
	@rm -rf coverage-*.xml

clean-docker: ## Clean - Clean Docker resources
	@$(MAKE) docker-clean

clean-all: ## Clean - Clean everything (build artifacts, Docker, etc.)
	@$(MAKE) clean
	@$(MAKE) clean-docker

# Security Commands
security-scan: ## Security - Run security scans
	@echo "$(BLUE)Running security scans...$(RESET)"
	@cd $(FLASK_DIR) && pip-audit -r requirements.txt 2>/dev/null || echo "$(YELLOW)pip-audit not installed$(RESET)"
	@cd $(WEBUI_DIR) && npm audit 2>/dev/null || true

audit: ## Security - Run security audit
	@echo "$(BLUE)Running security audit...$(RESET)"
	@$(MAKE) security-scan

# Monitoring Commands
metrics: ## Monitoring - Show application metrics
	@echo "$(BLUE)Application metrics:$(RESET)"
	@curl -s http://localhost:5000/metrics 2>/dev/null | head -20 || echo "Flask metrics not available"
	@curl -s http://localhost:8080/metrics 2>/dev/null | head -20 || echo "Go metrics not available"

monitor: ## Monitoring - Open monitoring dashboard
	@echo "$(BLUE)Grafana: http://localhost:3001$(RESET)"

# Documentation Commands
docs-serve: ## Documentation - Serve documentation locally
	@echo "$(BLUE)Serving documentation...$(RESET)"
	@cd docs && python3 -m http.server 8888

docs-build: ## Documentation - Build documentation
	@echo "$(BLUE)Building documentation...$(RESET)"
	@echo "Documentation is in docs/ directory (Markdown format)"

# Info Commands
info: ## Info - Show project information
	@echo "$(BLUE)Project Information:$(RESET)"
	@echo "Name: $(PROJECT_NAME)"
	@echo "Version: $(VERSION)"
	@echo "Go Version: $(GO_VERSION)"
	@echo "Python Version: $(PYTHON_VERSION)"
	@echo "Node Version: $(NODE_VERSION)"
	@echo ""
	@echo "$(BLUE)Service URLs:$(RESET)"
	@echo "Flask API:   http://localhost:5000"
	@echo "Go XDP:      http://localhost:8080"
	@echo "WebUI:       http://localhost:3000"
	@echo "Prometheus:  http://localhost:9090"
	@echo "Grafana:     http://localhost:3001"

env: ## Info - Show environment variables
	@echo "$(BLUE)Environment Variables:$(RESET)"
	@env | grep -E "^(LICENSE_|POSTGRES_|REDIS_|NODE_|GIN_|FLASK_|DB_)" | sort
