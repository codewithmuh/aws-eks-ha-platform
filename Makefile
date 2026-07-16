# aws-eks-ha-platform — one-command workflows.
# Run `make help` for the list.

SHELL := /bin/bash
.DEFAULT_GOAL := help

COMPOSE := docker compose
KIND_CLUSTER := ha-platform

## ----------------------------------------------------------------------------
## Local (Docker Compose) — the "before"
## ----------------------------------------------------------------------------
.PHONY: up
up: ## Build + start the whole stack locally (Compose)
	$(COMPOSE) up -d --build
	@echo "login:8081  authorize:8082  worker-a:8083  worker-b:8084"

.PHONY: down
down: ## Stop the local stack (keep volumes)
	$(COMPOSE) down

.PHONY: clean
clean: ## Stop the local stack and delete volumes
	$(COMPOSE) down -v

.PHONY: logs
logs: ## Tail all local logs
	$(COMPOSE) logs -f

.PHONY: smoke
smoke: ## Run the end-to-end smoke test against the local stack
	./scripts/smoke-test.sh

.PHONY: fencing-demo
fencing-demo: ## Kill the current leader and show failover + fencing (Compose)
	./scripts/fencing-demo.sh

## ----------------------------------------------------------------------------
## Kubernetes (kind) — the HA demo, free and local
## ----------------------------------------------------------------------------
.PHONY: kind-up
kind-up: ## Create a 3-"zone" kind cluster + load images + deploy via Helm
	./scripts/kind-up.sh

.PHONY: kind-down
kind-down: ## Delete the kind cluster
	kind delete cluster --name $(KIND_CLUSTER)

.PHONY: chaos
chaos: ## Kill a node under load and watch the platform survive (kind)
	./scripts/chaos-node-loss.sh

## ----------------------------------------------------------------------------
## AWS (EKS + managed services) — production profile
## ----------------------------------------------------------------------------
.PHONY: aws-plan
aws-plan: ## terraform plan for EKS + RDS + ElastiCache + MSK
	cd infra && terraform init -input=false && terraform plan

.PHONY: aws-apply
aws-apply: ## Provision the AWS platform (COSTS MONEY — read docs/runbooks first)
	cd infra && terraform apply

.PHONY: aws-destroy
aws-destroy: ## Tear down all AWS resources
	cd infra && terraform destroy

## ----------------------------------------------------------------------------
.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
