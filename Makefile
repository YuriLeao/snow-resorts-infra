# Snow Resorts — infrastructure & local dev orchestration.
# Local dev is $0: backing services run in Docker Compose. The microservices themselves
# run from their own repos (snow-resorts-auth-service, -user-service, ...) with the `local` Spring profile.

COMPOSE := docker compose -f docker/docker-compose.yml
# Use 5433 when a native Postgres already owns 5432 (common on macOS with EDB/Homebrew installs).
# `nc -z` is more reliable than `lsof` here — on some Macs lsof misses postgres listeners.
# Override: `make up POSTGRES_PORT=5434`
ifeq ($(origin POSTGRES_PORT),command line)
  export POSTGRES_PORT
else
  POSTGRES_PORT := $(shell if nc -z 127.0.0.1 5432 >/dev/null 2>&1; then echo 5433; else echo 5432; fi)
  export POSTGRES_PORT
endif

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

## ───────────────────────── Local infra ($0) ─────────────────────────

.PHONY: dev
dev: up seed ## Boot local infra (Postgres+PostGIS, Redis, MinIO, nginx gateway) and seed demo data
	@echo "Local stack is up. Postgres :$(POSTGRES_PORT)  Redis :6379  MinIO :9000 (console :9001)  Mailpit SMTP :1025 (UI :8025)  Gateway :8080"
	@if [ "$(POSTGRES_PORT)" != "5432" ]; then \
	  echo "NOTE: Postgres is on :$(POSTGRES_PORT) (5432 is busy). Export before starting Java services:"; \
	  echo "  export POSTGRES_PORT=$(POSTGRES_PORT)"; \
	fi
	@echo "Now run each service from its repo, e.g.: (cd ../snow-resorts-auth-service && ./mvnw spring-boot:run)"
	@echo "auth-service (local profile) auto-seeds demo@snow-resorts.com / Password123! on first startup."
	@echo "Re-run 'make seed' after user/resort services migrate to load resorts catalog + demo profile."
	@echo "API gateway (nginx, mirrors prod ALB) routes http://localhost:8080/snow-resort-service/v1/* to the host services on :8081-8085"

.PHONY: up
up: ## Start infra containers (Postgres, Redis, MinIO, Mailpit, nginx gateway :8080) in the background
	@echo "Postgres host port: $(POSTGRES_PORT)"
	@echo "POSTGRES_PORT=$(POSTGRES_PORT)" > .env
	$(COMPOSE) up -d
	@$(COMPOSE) ps

.PHONY: down
down: ## Stop infra containers (keep volumes)
	$(COMPOSE) down

.PHONY: clean-data
clean-data: ## Stop infra and DELETE local volumes (full reset)
	$(COMPOSE) down -v

.PHONY: logs
logs: ## Tail infra container logs
	$(COMPOSE) logs -f

.PHONY: config
config: ## Validate the docker-compose file
	$(COMPOSE) config

.PHONY: seed
seed: ## Seed demo data (idempotent; re-run after services migrate)
	@bash scripts/seed.sh

## ───────────────────────── Terraform ─────────────────────────

.PHONY: tf-staging-plan
tf-staging-plan: ## terraform plan for staging
	cd terraform/envs/staging && terraform init && terraform plan

.PHONY: tf-prod-plan
tf-prod-plan: ## terraform plan for prod
	cd terraform/envs/prod && terraform init && terraform plan
