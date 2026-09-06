# OpenShift AI Installation Toolkit - Makefile
# Provides CLI interface for automation and CI/CD pipelines
#
# Usage:
#   make help                    - Show all available targets
#   make setup-rhoai             - Install RHOAI 3.0 with all operators
#   make setup-demo              - Setup demo environment (MinIO, tools)
#   make gpu-machineset          - Create GPU worker nodes
#   make download-model MODEL=Qwen/Qwen3-8B MODE=s3
#   make serve-model NAME=qwen3 PATH=Qwen/Qwen3-8B MODE=s3

SHELL := /bin/bash
BASE := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
NAMESPACE ?= demo

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[1;33m
CYAN := \033[0;36m
NC := \033[0m

.PHONY: help
help:
	@echo ""
	@echo -e "$(CYAN)╔════════════════════════════════════════════════════════════════╗$(NC)"
	@echo -e "$(CYAN)║     OpenShift AI Installation Toolkit - Makefile Interface     ║$(NC)"
	@echo -e "$(CYAN)╚════════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo -e "$(YELLOW)Installation:$(NC)"
	@echo "  make setup-rhoai-35        Install RHOAI 3.5 with all prerequisites (recommended)"
	@echo "  make setup-rhoai-34        Install RHOAI 3.4 with all prerequisites"
	@echo "  make setup-users           Create demo users with htpasswd + groups"
	@echo "  make setup-rhoai-33        Install RHOAI 3.3 with all prerequisites"
	@echo "  make setup-rhoai           Install RHOAI 3.0 with all operators"
	@echo "  make setup-operators       Install only operators (NFD, GPU, Kueue, LWS)"
	@echo "  make setup-llmd            Setup llm-d infrastructure (Gateway, LWS, Kuadrant)"
	@echo ""
	@echo -e "$(YELLOW)GPU Management:$(NC)"
	@echo "  make gpu-machineset        Create GPU MachineSet (interactive)"
	@echo "  make gpu-machineset-spot   Create GPU MachineSet with spot instances"
	@echo ""
	@echo -e "$(YELLOW)Model Management:$(NC)"
	@echo "  make download-model        Download model from HuggingFace"
	@echo "                             MODE=s3|pvc MODEL=<hf-repo>"
	@echo "  make serve-model           Deploy model for serving"
	@echo "                             MODE=s3|pvc|oci NAME=<name> PATH=<path>"
	@echo ""
	@echo -e "$(YELLOW)Demo & Tools:$(NC)"
	@echo "  make setup-demo            Setup demo environment (MinIO, Open WebUI)"
	@echo "  make setup-demo-environment Deploy full demo environment (all components)"
	@echo "  make setup-mcp-kubernetes  Deploy Kubernetes MCP server"
	@echo "  make setup-benchmarks      Deploy GuideLLM and Benchmark Arena"
	@echo "  make setup-model-catalog   Configure custom model catalog"
	@echo "  make manage-model-catalog  Interactive model catalog management"
	@echo "  make deploy-n8n            Deploy n8n workflow automation"
	@echo "  make deploy-financial-loan Deploy financial loan demo"
	@echo "  make deploy-pipeline-demo  Deploy AI pipeline demo (KFP + Elyra)"
	@echo "  make deploy-nemo-guardrails Deploy NeMo Guardrails (RHOAI 3.4)"
	@echo "  make deploy-lemonade-stand Deploy Lemonade Stand Chat (NeMo Edition)"
	@echo "  make deploy-lmeval-lab     Deploy LMEval Builder Lab"
	@echo "  make deploy-maas-ratelimit Deploy MaaS Rate Limiting Demo"
	@echo "  make deploy-automl         Deploy AutoML Demo (Tech Preview)"
	@echo "  make deploy-autorag        Deploy AutoRAG Demo (Tech Preview)"
	@echo "  make deploy-open-webui     Deploy Open WebUI in own namespace"
	@echo ""
	@echo -e "$(YELLOW)Utilities:$(NC)"
	@echo "  make check-operators       Check operator installation status"
	@echo "  make cleanup-local         Clean up local files only"
	@echo "  make cleanup-all           Full cleanup (AWS resources)"
	@echo ""
	@echo -e "$(YELLOW)Interactive Mode:$(NC)"
	@echo "  make interactive           Launch interactive menu (rhoai-toolkit.sh)"
	@echo ""
	@echo -e "$(GREEN)Examples:$(NC)"
	@echo "  make download-model MODE=s3 MODEL=Qwen/Qwen3-8B"
	@echo "  make serve-model MODE=oci NAME=qwen3 PATH=oci://registry.redhat.io/rhelai1/modelcar-qwen3-8b:1.5"
	@echo "  make gpu-machineset-spot INSTANCE_TYPE=g6e.4xlarge"
	@echo ""

# =============================================================================
# Interactive Mode
# =============================================================================

.PHONY: interactive
interactive:
	@$(BASE)/rhoai-toolkit.sh

# =============================================================================
# Installation Targets
# =============================================================================

.PHONY: setup-rhoai-35
setup-rhoai-35:
	@echo -e "$(GREEN)▶ Installing RHOAI 3.5...$(NC)"
	@$(BASE)/scripts/install-rhoai-35.sh
	@echo -e "$(GREEN)✓ RHOAI 3.5 installation complete$(NC)"

.PHONY: setup-rhoai-34
setup-rhoai-34:
	@echo -e "$(GREEN)▶ Installing RHOAI 3.4...$(NC)"
	@$(BASE)/scripts/install-rhoai-34.sh
	@echo -e "$(GREEN)✓ RHOAI 3.4 installation complete$(NC)"

.PHONY: setup-users
setup-users:
	@echo -e "$(GREEN)▶ Setting up demo users...$(NC)"
	@$(BASE)/scripts/setup-users.sh $(ARGS)
	@echo -e "$(GREEN)✓ User setup complete$(NC)"

.PHONY: setup-rhoai-33
setup-rhoai-33:
	@echo -e "$(GREEN)▶ Installing RHOAI 3.3...$(NC)"
	@$(BASE)/scripts/install-rhoai-33.sh
	@echo -e "$(GREEN)✓ RHOAI 3.3 installation complete$(NC)"

.PHONY: setup-rhoai
setup-rhoai: setup-operators
	@echo -e "$(GREEN)▶ Installing RHOAI Operator...$(NC)"
	@$(BASE)/rhoai-toolkit.sh --non-interactive --install-rhoai
	@echo -e "$(GREEN)✓ RHOAI installation complete$(NC)"

.PHONY: setup-operators
setup-operators:
	@echo -e "$(GREEN)▶ Installing prerequisite operators...$(NC)"
	@$(BASE)/scripts/check-operator-install-status.sh nfd openshift-nfd 300 || \
		(oc apply -f $(BASE)/lib/manifests/operators/nfd-operator.yaml && \
		 $(BASE)/scripts/check-operator-install-status.sh nfd openshift-nfd 300)
	@$(BASE)/scripts/check-operator-install-status.sh gpu-operator-certified nvidia-gpu-operator 300 || \
		(oc apply -f $(BASE)/lib/manifests/operators/gpu-operator.yaml && \
		 $(BASE)/scripts/check-operator-install-status.sh gpu-operator-certified nvidia-gpu-operator 300)
	@echo -e "$(GREEN)✓ Operators installed$(NC)"

.PHONY: setup-llmd
setup-llmd:
	@echo -e "$(GREEN)▶ Setting up llm-d infrastructure...$(NC)"
	@$(BASE)/rhoai-toolkit.sh --non-interactive --setup-llmd
	@echo -e "$(GREEN)✓ llm-d infrastructure ready$(NC)"

# =============================================================================
# GPU Management
# =============================================================================

.PHONY: gpu-machineset
gpu-machineset:
	@$(BASE)/scripts/create-gpu-machineset.sh

.PHONY: gpu-machineset-spot
gpu-machineset-spot:
	@$(BASE)/scripts/create-gpu-machineset.sh --spot $(if $(INSTANCE_TYPE),--instance-type $(INSTANCE_TYPE),)

# =============================================================================
# Model Management
# =============================================================================

.PHONY: download-model
download-model:
ifndef MODEL
	$(error MODEL is required. Usage: make download-model MODE=s3 MODEL=Qwen/Qwen3-8B)
endif
	@$(BASE)/scripts/download-model.sh $(or $(MODE),s3) $(MODEL)

.PHONY: serve-model
serve-model:
ifndef NAME
	$(error NAME is required. Usage: make serve-model MODE=s3 NAME=qwen3 PATH=Qwen/Qwen3-8B)
endif
ifndef PATH
	$(error PATH is required. Usage: make serve-model MODE=s3 NAME=qwen3 PATH=Qwen/Qwen3-8B)
endif
	@$(BASE)/scripts/serve-model.sh $(or $(MODE),s3) $(NAME) $(PATH) $(EXTRA_ARGS)

# =============================================================================
# Demo & Tools
# =============================================================================

.PHONY: setup-demo
setup-demo: setup-namespace setup-minio
	@echo -e "$(GREEN)▶ Setting up demo tools...$(NC)"
	@oc apply -f $(BASE)/lib/manifests/demo/guidellm.yaml -n $(NAMESPACE) 2>/dev/null || true
	@oc apply -f $(BASE)/lib/manifests/demo/benchmark-arena.yaml -n $(NAMESPACE) 2>/dev/null || true
	@echo -e "$(GREEN)✓ Demo environment ready$(NC)"

.PHONY: setup-namespace
setup-namespace:
	@oc get namespace $(NAMESPACE) >/dev/null 2>&1 || oc new-project $(NAMESPACE)
	@oc label namespace $(NAMESPACE) \
		modelmesh-enabled=false \
		opendatahub.io/dashboard=true \
		--overwrite 2>/dev/null || true

.PHONY: setup-minio
setup-minio:
	@echo -e "$(GREEN)▶ Setting up MinIO...$(NC)"
	@oc apply -f $(BASE)/lib/manifests/demo/minio.yaml -n $(NAMESPACE)
	@echo "Waiting for MinIO to be ready..."
	@until oc get statefulset minio -n $(NAMESPACE) -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q '1'; do \
		sleep 5; \
	done
	@echo -e "$(GREEN)✓ MinIO ready$(NC)"

.PHONY: setup-mcp-kubernetes
setup-mcp-kubernetes:
	@echo -e "$(GREEN)▶ Deploying Kubernetes MCP Server...$(NC)"
	@oc apply -f $(BASE)/lib/manifests/demo/mcp-kubernetes.yaml -n $(NAMESPACE)
	@echo -e "$(GREEN)✓ Kubernetes MCP Server deployed$(NC)"

.PHONY: setup-benchmarks
setup-benchmarks:
	@echo -e "$(GREEN)▶ Deploying benchmarking tools...$(NC)"
	@oc apply -f $(BASE)/lib/manifests/demo/guidellm.yaml -n $(NAMESPACE)
	@oc apply -f $(BASE)/lib/manifests/demo/benchmark-arena.yaml -n $(NAMESPACE)
	@echo -e "$(GREEN)✓ Benchmarking tools deployed$(NC)"
	@echo ""
	@echo "GuideLLM: oc rsh \$$(oc get pod -l app=guidellm -o name) guidellm benchmark run ..."
	@echo "Benchmark Arena: https://$$(oc get route benchmark-arena -n $(NAMESPACE) -o jsonpath='{.spec.host}')"

.PHONY: setup-model-catalog
setup-model-catalog:
	@echo -e "$(GREEN)▶ Configuring custom model catalog...$(NC)"
	@oc apply -f $(BASE)/lib/manifests/demo/custom-model-catalog.yaml
	@oc delete pods -l app.kubernetes.io/name=model-catalog -n rhoai-model-registries 2>/dev/null || true
	@echo -e "$(GREEN)✓ Model catalog configured$(NC)"

# =============================================================================
# Full Demo Environment
# =============================================================================

.PHONY: setup-demo-environment
setup-demo-environment:
	@echo -e "$(GREEN)▶ Deploying full demo environment...$(NC)"
	@$(BASE)/scripts/deploy-demo-environment.sh --skip-core
	@echo -e "$(GREEN)✓ Demo environment deployed$(NC)"

.PHONY: deploy-n8n
deploy-n8n:
	@$(BASE)/demo/n8n-demo/deploy.sh

.PHONY: deploy-financial-loan
deploy-financial-loan:
	@$(BASE)/demo/financial-loan-demo/deploy.sh

.PHONY: deploy-pipeline-demo
deploy-pipeline-demo:
	@$(BASE)/demo/pipeline-demo/deploy.sh

.PHONY: deploy-nemo-guardrails
deploy-nemo-guardrails:
	@$(BASE)/demo/nemo-guardrails-demo/deploy.sh

.PHONY: deploy-lemonade-stand
deploy-lemonade-stand:
	@$(BASE)/demo/lemonade-stand-demo/deploy.sh

.PHONY: deploy-lmeval-lab
deploy-lmeval-lab:
	@$(BASE)/demo/lmeval-demo/deploy.sh

.PHONY: deploy-maas-ratelimit
deploy-maas-ratelimit:
	@$(BASE)/demo/maas-ratelimit-demo/deploy.sh

.PHONY: deploy-automl
deploy-automl:
	@$(BASE)/demo/automl-demo/deploy.sh

.PHONY: deploy-autorag
deploy-autorag:
	@$(BASE)/demo/autorag-demo/deploy.sh

.PHONY: deploy-open-webui
deploy-open-webui:
	@$(BASE)/demo/open-webui-demo/deploy.sh

.PHONY: manage-model-catalog
manage-model-catalog:
	@$(BASE)/scripts/manage-model-catalog.sh

# =============================================================================
# Utilities
# =============================================================================

.PHONY: check-operators
check-operators:
	@echo -e "$(CYAN)Checking operator status...$(NC)"
	@echo ""
	@echo "NFD Operator:"
	@oc get csv -n openshift-nfd 2>/dev/null | grep -E "nfd|NAME" || echo "  Not installed"
	@echo ""
	@echo "GPU Operator:"
	@oc get csv -n nvidia-gpu-operator 2>/dev/null | grep -E "gpu|NAME" || echo "  Not installed"
	@echo ""
	@echo "RHOAI Operator:"
	@oc get csv -n redhat-ods-operator 2>/dev/null | grep -E "rhods|NAME" || echo "  Not installed"
	@echo ""
	@echo "Kueue Operator:"
	@oc get csv -n openshift-operators 2>/dev/null | grep -E "kueue|NAME" || echo "  Not installed"
	@echo ""
	@echo "LWS Operator:"
	@oc get csv -n openshift-lws-operator 2>/dev/null | grep -E "leader-worker|NAME" || echo "  Not installed"

.PHONY: cleanup-local
cleanup-local:
	@$(BASE)/scripts/cleanup-all.sh --local-only

.PHONY: cleanup-all
cleanup-all:
	@$(BASE)/scripts/cleanup-all.sh

# =============================================================================
# Show URLs
# =============================================================================

.PHONY: show-urls
show-urls:
	@echo -e "$(CYAN)Service URLs:$(NC)"
	@echo ""
	@echo "RHOAI Dashboard:"
	@echo "  https://$$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}' 2>/dev/null || echo 'Not available')"
	@echo ""
	@echo "OpenShift Console:"
	@echo "  $$(oc whoami --show-console 2>/dev/null || echo 'Not connected')"
	@echo ""
	@if oc get route benchmark-arena -n $(NAMESPACE) >/dev/null 2>&1; then \
		echo "Benchmark Arena:"; \
		echo "  https://$$(oc get route benchmark-arena -n $(NAMESPACE) -o jsonpath='{.spec.host}')"; \
		echo ""; \
	fi
	@if oc get route open-webui -n $(NAMESPACE) >/dev/null 2>&1; then \
		echo "Open WebUI:"; \
		echo "  https://$$(oc get route open-webui -n $(NAMESPACE) -o jsonpath='{.spec.host}')"; \
		echo ""; \
	fi
	@if oc get route open-webui -n open-webui >/dev/null 2>&1; then \
		echo "Open WebUI (standalone):"; \
		echo "  https://$$(oc get route open-webui -n open-webui -o jsonpath='{.spec.host}')"; \
		echo ""; \
	fi
	@if oc get route n8n -n n8n >/dev/null 2>&1; then \
		echo "n8n:"; \
		echo "  https://$$(oc get route n8n -n n8n -o jsonpath='{.spec.host}')"; \
		echo ""; \
	fi
	@if oc get route evalhub -n lmeval-demo >/dev/null 2>&1; then \
		echo "EvalHub:"; \
		echo "  https://$$(oc get route evalhub -n lmeval-demo -o jsonpath='{.spec.host}')"; \
		echo ""; \
	fi
