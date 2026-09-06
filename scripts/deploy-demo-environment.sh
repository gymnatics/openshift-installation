#!/bin/bash
################################################################################
# Deploy Full RHOAI Demo Environment
################################################################################
# Orchestrates deployment of all demo components onto a RHOAI 3.4 cluster.
# Each component is independently deployable via its own demo/*/deploy.sh.
#
# Usage:
#   ./deploy-demo-environment.sh                      # Deploy everything
#   ./deploy-demo-environment.sh --skip-core           # Skip RHOAI/MaaS setup
#   ./deploy-demo-environment.sh --components feast,n8n # Deploy specific components
#   ./deploy-demo-environment.sh --exclude marketing   # Skip specific components
#   ./deploy-demo-environment.sh --list                # List available components
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/lib/utils/colors.sh"
source "$ROOT_DIR/lib/utils/common.sh"
source "$ROOT_DIR/lib/functions/external-repos.sh"

# Component registry: name|deploy_function|description|default_on
COMPONENTS=(
    "feast|deploy_feast|Feast Banking Feature Store Demo|yes"
    "mcp|deploy_mcp|Kubernetes MCP Server + AI Playground|yes"
    "maas|deploy_maas|MaaS Model Deployment|yes"
    "financial-loan|deploy_financial_loan|Micro Financial Loan (Predictive + GenAI)|yes"
    "pipeline|deploy_pipeline|AI Pipeline Demo (KFP + Elyra)|yes"
    "open-webui|deploy_open_webui_demo|Open WebUI Chat Interface|yes"
    "n8n|deploy_n8n|n8n Workflow Automation|yes"
    "model-catalog|deploy_model_catalog|Custom Model Catalog|yes"
    "nemo-guardrails|deploy_nemo_guardrails_demo|NeMo Guardrails (RHOAI 3.4)|yes"
    "lemonade-stand|deploy_lemonade_stand|Lemonade Stand Chat (NeMo Guardrails Edition)|yes"
    "lmeval|deploy_lmeval|LMEval + EvalHub (TP) Evaluation Stack|yes"
    "maas-ratelimit|deploy_maas_ratelimit|MaaS Rate Limiting Demo (API Key + 429)|yes"
    "automl|deploy_automl|AutoML (TP) Automated Model Training|yes"
    "autorag|deploy_autorag|AutoRAG (TP) RAG Pipeline Optimization|yes"
    "mlflow-tracing|deploy_mlflow_tracing|MLflow Tracing Demo (Banking Multi-Agent)|yes"
    "lightspeed|deploy_lightspeed|Lightspeed + MCP Troubleshooting Demo|yes"
    "nim|deploy_nim_demo|NVIDIA NIM (Nemotron via NVAIE)|no"
    "marketing|deploy_marketing|Marketing Assistant (3x L40S GPU)|no"
)

SKIP_CORE=false
COMPONENT_LIST=""
EXCLUDE_LIST=""
DEFAULT_MODEL="${MODEL:-Qwen3-4B}"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --skip-core            Skip RHOAI/MaaS/GPU setup (assume already installed)"
    echo "  --components LIST      Comma-separated list of components to deploy"
    echo "  --exclude LIST         Comma-separated list of components to skip"
    echo "  --model MODEL          Default model for demos (default: $DEFAULT_MODEL)"
    echo "  --list                 List available components"
    echo "  --status               Check what's already deployed"
    echo "  -h, --help             Show this help"
    echo ""
}

list_components() {
    echo ""
    printf "  %-20s %-7s %s\n" "COMPONENT" "DEFAULT" "DESCRIPTION"
    printf "  %-20s %-7s %s\n" "---------" "-------" "-----------"
    for entry in "${COMPONENTS[@]}"; do
        IFS='|' read -r name _ desc default <<< "$entry"
        printf "  %-20s %-7s %s\n" "$name" "$default" "$desc"
    done
    echo ""
}

check_status() {
    if ! oc whoami &>/dev/null; then
        echo -e "${RED}Not logged in to OpenShift.${NC}"
        exit 1
    fi

    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║               Demo Environment Status                        ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Check each component by looking for its namespace or key resources
    check_component() {
        local name="$1"
        local desc="$2"
        local check_cmd="$3"
        if eval "$check_cmd" &>/dev/null 2>&1; then
            printf "  ${GREEN}✓${NC}  %-22s %s\n" "$name" "$desc"
        else
            printf "  ${RED}✗${NC}  %-22s %s\n" "$name" "$desc"
        fi
    }

    echo -e "${CYAN}  Platform:${NC}"
    check_component "RHOAI" "Operator installed" \
        "oc get namespace redhat-ods-applications"
    check_component "GPU Nodes" "$(oc get nodes -l nvidia.com/gpu.present=true --no-headers 2>/dev/null | wc -l | tr -d ' ') GPU node(s)" \
        "oc get nodes -l nvidia.com/gpu.present=true --no-headers 2>/dev/null | grep -q ."
    echo ""

    echo -e "${CYAN}  Models:${NC}"
    ISVC=$(oc get inferenceservice -A --no-headers 2>/dev/null | awk '{print $2 " (" $1 ")"}')
    LLMISVC=$(oc get llminferenceservice -A --no-headers 2>/dev/null | awk '{print $2 " (" $1 ")"}')
    if [ -n "$ISVC" ] || [ -n "$LLMISVC" ]; then
        echo "$ISVC" "$LLMISVC" | while read -r line; do
            [ -n "$line" ] && printf "  ${GREEN}✓${NC}  %-22s %s\n" "Model" "$line"
        done
    else
        printf "  ${RED}✗${NC}  %-22s %s\n" "Models" "None deployed"
    fi
    echo ""

    echo -e "${CYAN}  Demo Components:${NC}"
    check_component "feast" "Feast Banking Demo" \
        "oc get namespace a-rh-dept"
    check_component "mcp" "MCP Servers" \
        "oc get configmap gen-ai-aa-mcp-servers -n redhat-ods-applications"
    check_component "financial-loan" "Financial Loan Demo" \
        "oc get namespace financial-loan-demo"
    check_component "pipeline" "AI Pipeline Demo" \
        "oc get namespace pipeline-demo"
    check_component "open-webui" "Open WebUI" \
        "oc get deployment open-webui -n open-webui"
    check_component "n8n" "n8n Workflow Automation" \
        "oc get deployment n8n -n n8n"
    check_component "model-catalog" "Custom Model Catalog" \
        "oc get configmap model-catalog-sources -n redhat-ods-applications"
    check_component "nemo-guardrails" "NeMo Guardrails" \
        "oc get namespace nemo-guardrails-demo"
    check_component "lmeval" "LMEval + EvalHub" \
        "oc get namespace lmeval-demo"
    check_component "maas-ratelimit" "MaaS Rate Limiting" \
        "oc get namespace maas-ratelimit-demo"
    check_component "automl" "AutoML (TP)" \
        "oc get namespace automl-demo"
    check_component "autorag" "AutoRAG (TP)" \
        "oc get namespace autorag-demo"
    check_component "marketing" "Marketing Assistant" \
        "oc get namespace marketing-assistant"
    check_component "nim" "NVIDIA NIM" \
        "oc get inferenceservice -n nim-demo --no-headers 2>/dev/null | grep -q nim"
    echo ""

    echo -e "${CYAN}  Workbenches (namespaces that need one):${NC}"
    local _wb_namespaces=("financial-loan-demo" "pipeline-demo" "lmeval-demo" "maas-ratelimit-demo")
    local _wb_descs=("ML training + LLM fine-tuning" "KFP SDK + Elyra pipelines" "EvalHub SDK + Korean benchmarks" "API key auth + rate limiting")
    local _needs_wb=0
    for i in "${!_wb_namespaces[@]}"; do
        local _wns="${_wb_namespaces[$i]}"
        local _wdesc="${_wb_descs[$i]}"
        if oc get namespace "$_wns" &>/dev/null 2>&1; then
            local _wcount=$(oc get notebooks.kubeflow.org -n "$_wns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
            if [ "$_wcount" -gt 0 ]; then
                printf "  ${GREEN}✓${NC}  %-28s %s\n" "$_wns" "Workbench exists"
            else
                printf "  ${YELLOW}○${NC}  %-28s %s\n" "$_wns" "Needs workbench -- $_wdesc"
                _needs_wb=$((_needs_wb + 1))
            fi
        fi
    done
    if [ $_needs_wb -gt 0 ]; then
        echo ""
        echo "    Create workbenches in RHOAI Dashboard, then in each terminal:"
        echo "      git clone https://github.com/gymnatics/RHOAI-Toolkit.git"
    elif [ $_needs_wb -eq 0 ]; then
        local _any_ns=false
        for _wns in "${_wb_namespaces[@]}"; do
            oc get namespace "$_wns" &>/dev/null 2>&1 && _any_ns=true
        done
        if [ "$_any_ns" = false ]; then
            printf "  ${YELLOW}-${NC}  %-28s %s\n" "(none)" "No workbench-requiring demos deployed yet"
        fi
    fi
    echo ""

    echo -e "${CYAN}  Web UIs:${NC}"
    for route_name in open-webui n8n evalhub; do
        url=$(oc get route "$route_name" -A -o jsonpath='{.items[0].status.ingress[0].host}' 2>/dev/null)
        if [ -n "$url" ]; then
            printf "  ${GREEN}✓${NC}  %-22s https://%s\n" "$route_name" "$url"
        fi
    done
    DASHBOARD_URL=$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.status.ingress[0].host}' 2>/dev/null)
    [ -n "$DASHBOARD_URL" ] && printf "  ${GREEN}✓${NC}  %-22s https://%s\n" "RHOAI Dashboard" "$DASHBOARD_URL"
    echo ""

    # Show what's NOT deployed
    echo -e "${YELLOW}  To deploy missing components:${NC}"
    echo "    ./scripts/deploy-demo-environment.sh --skip-core --components <name1,name2>"
    echo ""
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-core) SKIP_CORE=true; shift ;;
        --components) COMPONENT_LIST="$2"; shift 2 ;;
        --exclude) EXCLUDE_LIST="$2"; shift 2 ;;
        --model) DEFAULT_MODEL="$2"; shift 2 ;;
        --list) list_components; exit 0 ;;
        --status) check_status; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

is_deployed() {
    local name="$1"
    case "$name" in
        feast)           oc get namespace a-rh-dept &>/dev/null 2>&1 ;;
        mcp)             oc get configmap gen-ai-aa-mcp-servers -n redhat-ods-applications &>/dev/null 2>&1 ;;
        maas)            oc get llminferenceservice -A --no-headers 2>/dev/null | grep -q . ;;
        financial-loan)  oc get namespace financial-loan-demo &>/dev/null 2>&1 && \
                         oc get deployment microloan-webapp -n financial-loan-demo &>/dev/null 2>&1 ;;
        pipeline)        oc get datasciencepipelinesapplication pipelines-definition -n pipeline-demo &>/dev/null 2>&1 ;;
        open-webui)      oc get deployment open-webui -n open-webui &>/dev/null 2>&1 ;;
        n8n)             oc get deployment n8n -n n8n &>/dev/null 2>&1 ;;
        model-catalog)   oc get configmap model-catalog-sources -n redhat-ods-applications &>/dev/null 2>&1 ;;
        nemo-guardrails) oc get namespace nemo-guardrails-demo &>/dev/null 2>&1 ;;
        lemonade-stand) oc get deployment lemonade-stand -n nemo-guardrails-demo &>/dev/null 2>&1 ;;
        lmeval)          oc get namespace lmeval-demo &>/dev/null 2>&1 && \
                         oc get sa lmeval-sa -n lmeval-demo &>/dev/null 2>&1 ;;
        maas-ratelimit)  oc get namespace maas-ratelimit-demo &>/dev/null 2>&1 ;;
        automl)          oc get namespace automl-demo &>/dev/null 2>&1 && \
                         oc get deployment minio -n automl-demo &>/dev/null 2>&1 ;;
        autorag)         oc get namespace autorag-demo &>/dev/null 2>&1 && \
                         oc get deployment milvus-standalone -n autorag-demo &>/dev/null 2>&1 ;;
        marketing)       oc get namespace marketing-assistant &>/dev/null 2>&1 ;;
        nim)             oc get inferenceservice -n nim-demo --no-headers 2>/dev/null | grep -q nim ;;
        *)               return 1 ;;
    esac
}

should_deploy() {
    local name="$1"
    local default="$2"

    if [ -n "$COMPONENT_LIST" ]; then
        echo ",$COMPONENT_LIST," | grep -q ",$name," && return 0 || return 1
    fi

    if [ -n "$EXCLUDE_LIST" ]; then
        echo ",$EXCLUDE_LIST," | grep -q ",$name," && return 1
    fi

    [ "$default" = "yes" ] && return 0 || return 1
}

# Component deploy functions -- each calls the respective demo/*/deploy.sh

deploy_feast() {
    if [ -f "$ROOT_DIR/lib/functions/rhoai.sh" ]; then
        source "$ROOT_DIR/lib/functions/rhoai.sh" 2>/dev/null || true
        if type deploy_banking_demo &>/dev/null; then
            deploy_banking_demo
            return
        fi
    fi
    print_warning "Feast banking demo function not available"
}

deploy_mcp() {
    if [ -f "$ROOT_DIR/scripts/setup-mcp-servers.sh" ]; then
        bash "$ROOT_DIR/scripts/setup-mcp-servers.sh"
    else
        print_warning "MCP server setup script not found"
    fi
}

deploy_maas() {
    print_info "MaaS should be configured during RHOAI 3.4 installation."
    print_info "Use: scripts/deploy-llmd-model.sh to deploy a model to MaaS"
}

deploy_financial_loan() {
    bash "$ROOT_DIR/demo/financial-loan-demo/deploy.sh"
}

deploy_pipeline() {
    bash "$ROOT_DIR/demo/pipeline-demo/deploy.sh"
}

deploy_open_webui_demo() {
    bash "$ROOT_DIR/demo/open-webui-demo/deploy.sh"
}

deploy_n8n() {
    bash "$ROOT_DIR/demo/n8n-demo/deploy.sh"
}

deploy_model_catalog() {
    if [ -f "$ROOT_DIR/lib/manifests/demo/custom-model-catalog.yaml" ]; then
        oc apply -f "$ROOT_DIR/lib/manifests/demo/custom-model-catalog.yaml"
        print_success "Model catalog deployed"
    fi
}

deploy_nemo_guardrails_demo() {
    bash "$ROOT_DIR/demo/nemo-guardrails-demo/deploy.sh"
}

deploy_lemonade_stand() {
    bash "$ROOT_DIR/demo/lemonade-stand-demo/deploy.sh"
}

deploy_lmeval() {
    bash "$ROOT_DIR/demo/lmeval-demo/deploy.sh"
}

deploy_maas_ratelimit() {
    bash "$ROOT_DIR/demo/maas-ratelimit-demo/deploy.sh"
}

deploy_automl() {
    bash "$ROOT_DIR/demo/automl-demo/deploy.sh"
}

deploy_autorag() {
    bash "$ROOT_DIR/demo/autorag-demo/deploy.sh"
}

deploy_mlflow_tracing() {
    bash "$ROOT_DIR/demo/mlflow-tracing-demo/deploy.sh"
}

deploy_lightspeed() {
    bash "$ROOT_DIR/demo/lightspeed-demo/deploy.sh" deploy
}

deploy_marketing() {
    bash "$ROOT_DIR/demo/marketing-assistant-demo/deploy.sh"
}

deploy_nim_demo() {
    bash "$ROOT_DIR/demo/nim-demo/deploy.sh"
}

# Main execution

print_header "RHOAI Demo Environment Deployment"

if ! oc whoami &>/dev/null; then
    print_error "Not logged in to OpenShift. Run: oc login <cluster-url>"
    exit 1
fi

CLUSTER_DOMAIN=$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null)
print_info "Cluster: $CLUSTER_DOMAIN"
echo ""

if [ "$SKIP_CORE" = false ]; then
    print_step "Step 1: Core Platform"
    if [ -f "$ROOT_DIR/scripts/install-rhoai-35.sh" ]; then
        print_info "Run scripts/install-rhoai-35.sh separately for full RHOAI setup"
        print_info "Or use --skip-core if RHOAI is already installed"
        read -rp "Skip core setup and deploy demos only? (Y/n): " skip_confirm
        skip_confirm="${skip_confirm:-Y}"
        if [[ "$skip_confirm" =~ ^[Yy]$ ]]; then
            SKIP_CORE=true
        else
            bash "$ROOT_DIR/scripts/install-rhoai-35.sh"
        fi
    fi
fi

# --- GPU & Model Check ---
print_step "Step 2: GPU & Shared Model Check"
echo ""

GPU_NODES=$(oc get nodes -l nvidia.com/gpu.present=true --no-headers 2>/dev/null | wc -l | tr -d ' ')
GPU_COUNT=$(oc get nodes -l nvidia.com/gpu.present=true -o jsonpath='{range .items[*]}{.status.capacity.nvidia\.com/gpu}{"\n"}{end}' 2>/dev/null | awk '{s+=$1}END{print s+0}')
ISVC_COUNT=$(oc get inferenceservice -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
LLMISVC_COUNT=$(oc get llminferenceservice -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
TOTAL_MODELS=$((ISVC_COUNT + LLMISVC_COUNT))

if [ "$GPU_NODES" -gt 0 ]; then
    print_success "GPU nodes: $GPU_NODES (total GPUs: $GPU_COUNT)"
else
    print_warning "No GPU nodes detected. GPU-dependent demos will deploy but models won't serve until GPUs are available."
    print_info "Add GPUs with: ./scripts/create-gpu-machineset.sh"
fi

if [ "$TOTAL_MODELS" -gt 0 ]; then
    print_success "Deployed models: $TOTAL_MODELS"
    if [ "$ISVC_COUNT" -gt 0 ]; then
        oc get inferenceservice -A --no-headers 2>/dev/null | awk '{printf "    %-30s %-30s %s\n", $2, $1, "(InferenceService)"}'
    fi
    if [ "$LLMISVC_COUNT" -gt 0 ]; then
        oc get llminferenceservice -A --no-headers 2>/dev/null | awk '{printf "    %-30s %-30s %s\n", $2, $1, "(LLMInferenceService/MaaS)"}'
    fi
    echo ""
    print_info "Demos will auto-detect these model endpoints. No additional deployment needed."
else
    print_info "No models deployed yet."
    if [ "$GPU_COUNT" -gt 0 ] 2>/dev/null; then
        echo ""
        print_info "A shared LLM is recommended so all demos work end-to-end."
        print_info "You can deploy any OpenAI-compatible model (vLLM runtime)."
        echo ""
        echo "  1) Skip -- I'll deploy models myself later"
        echo "  2) Deploy a model now (I'll provide the HuggingFace model ID)"
        echo ""
        read -rp "Choice [1-2, default: 1]: " model_choice
        model_choice="${model_choice:-1}"

        if [ "$model_choice" = "2" ]; then
            echo ""
            print_info "Examples:"
            echo "    RedHatAI/Qwen3-4B-FP8-dynamic       (small, 1 GPU, ~8GB VRAM)"
            echo "    RedHatAI/Qwen3-8B-FP8-dynamic       (medium, 1 GPU, ~16GB VRAM)"
            echo "    RedHatAI/Qwen3-32B-FP8-dynamic      (large, 1 GPU L40S, ~20GB VRAM)"
            echo "    RedHatAI/granite-3.3-8b-instruct     (IBM Granite)"
            echo ""
            read -rp "HuggingFace model ID: " HF_MODEL_ID
            if [ -n "$HF_MODEL_ID" ]; then
                MODEL_SHORT=$(echo "$HF_MODEL_ID" | sed 's|.*/||' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')
                read -rp "Model serving name [$MODEL_SHORT]: " MODEL_NAME
                MODEL_NAME="${MODEL_NAME:-$MODEL_SHORT}"

                echo ""
                read -rp "Extra vLLM args (or Enter for defaults): " VLLM_ARGS
                VLLM_ARGS="${VLLM_ARGS:---max-model-len 8192 --gpu-memory-utilization 0.90 --enable-auto-tool-choice --tool-call-parser hermes}"

                if [ -f "$ROOT_DIR/scripts/serve-model.sh" ]; then
                    bash "$ROOT_DIR/scripts/serve-model.sh" s3 "$MODEL_NAME" "$HF_MODEL_ID" "$VLLM_ARGS" || true
                else
                    print_warning "serve-model.sh not found. Deploy manually:"
                    echo "    ./scripts/serve-model.sh s3 $MODEL_NAME $HF_MODEL_ID \"$VLLM_ARGS\""
                fi
            fi
        else
            print_info "Skipping model deployment. Demos will deploy but LLM features won't work until a model is available."
            echo ""
            print_info "Deploy a model anytime with:"
            echo "    ./scripts/serve-model.sh s3 <name> <HuggingFace-model-ID> \"<vllm-args>\""
            echo "    ./scripts/deploy-llmd-model.sh  (for MaaS/llm-d)"
        fi
    fi
fi

echo ""
print_step "Step 3: Pre-Deployment Status Check"
echo ""

ALREADY_DONE=0
TODO=0
TODO_LIST=""
for entry in "${COMPONENTS[@]}"; do
    IFS='|' read -r name _ desc default <<< "$entry"
    if should_deploy "$name" "$default"; then
        if is_deployed "$name"; then
            printf "  ${GREEN}✓${NC}  %-22s %s\n" "$name" "(already deployed)"
            ALREADY_DONE=$((ALREADY_DONE + 1))
        else
            printf "  ${YELLOW}○${NC}  %-22s %s\n" "$name" "(will deploy)"
            TODO=$((TODO + 1))
            TODO_LIST="${TODO_LIST}${name},"
        fi
    fi
done

echo ""
if [ $ALREADY_DONE -gt 0 ]; then
    print_info "Already deployed: $ALREADY_DONE components (will skip)"
fi
if [ $TODO -eq 0 ]; then
    print_success "All components are already deployed!"
    echo ""
    check_status
    exit 0
fi
print_info "To deploy: $TODO components"
echo ""
read -rp "Continue with deployment? (Y/n): " deploy_confirm
deploy_confirm="${deploy_confirm:-Y}"
if [[ ! "$deploy_confirm" =~ ^[Yy]$ ]]; then
    print_info "Deployment cancelled."
    exit 0
fi

echo ""
print_step "Step 4: Deploy Demo Components"
echo ""

DEPLOYED=0
SKIPPED=0
FAILED=0

for entry in "${COMPONENTS[@]}"; do
    IFS='|' read -r name func desc default <<< "$entry"

    if should_deploy "$name" "$default"; then
        if is_deployed "$name"; then
            print_info "Skipping $name (already deployed)"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
        echo ""
        print_step "Deploying: $desc..."
        if $func 2>&1; then
            print_success "$name deployed"
            DEPLOYED=$((DEPLOYED + 1))
        else
            print_error "$name failed"
            FAILED=$((FAILED + 1))
        fi
    else
        SKIPPED=$((SKIPPED + 1))
    fi
done

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║               Deployment Summary                             ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
print_success "Deployed: $DEPLOYED components"
[ $SKIPPED -gt 0 ] && print_info "Skipped: $SKIPPED components"
[ $FAILED -gt 0 ] && print_error "Failed: $FAILED components"
echo ""

print_info "Web UIs:"
for route_name in open-webui n8n; do
    url=$(oc get route "$route_name" -A -o jsonpath='{.items[0].status.ingress[0].host}' 2>/dev/null || \
          oc get route "$route_name" --all-namespaces -o jsonpath='{.items[0].status.ingress[0].host}' 2>/dev/null)
    [ -n "$url" ] && echo "  $route_name: https://$url"
done

DASHBOARD_URL=$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.status.ingress[0].host}' 2>/dev/null)
[ -n "$DASHBOARD_URL" ] && echo "  RHOAI Dashboard: https://$DASHBOARD_URL"
echo ""

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║               Next Steps: Workbenches                        ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Workbench-requiring demos: namespace|workbench-name|description
WB_DEMOS=(
    "lmeval-demo|model-benchmarking|EvalHub SDK + Korean benchmarks"
    "financial-loan-demo|model-training|ML training + LLM fine-tuning"
    "pipeline-demo|ai-pipelines|KFP SDK + Elyra pipelines"
    "maas-ratelimit-demo|rate-limit-testing|API key auth + rate limit testing"
)

for wb_entry in "${WB_DEMOS[@]}"; do
    IFS='|' read -r wb_ns wb_name wb_desc <<< "$wb_entry"
    if oc get namespace "$wb_ns" &>/dev/null 2>&1; then
        if oc get notebook "$wb_name" -n "$wb_ns" &>/dev/null 2>&1; then
            printf "  ${GREEN}✓${NC}  %-28s workbench: %s\n" "$wb_ns" "$wb_name"
        else
            printf "  ${YELLOW}○${NC}  %-28s workbench missing (re-run deploy.sh)\n" "$wb_ns"
        fi
    fi
done

echo ""
echo "  Workbenches are auto-provisioned by each deploy.sh."
echo "  RHOAI-Toolkit is auto-cloned into /opt/app-root/src/RHOAI-Toolkit."
echo "  If a repo is behind remote, a warning is printed — run 'git pull' manually."
echo ""
echo "  Vendored notebooks (auto-configured, no hardcoded URLs):"
echo "    financial-loan-demo: demo/financial-loan-demo/notebooks/"
echo "    lmeval-demo:         demo/lmeval-demo/notebooks/"
echo ""

# Dashboard-only features
DASHBOARD_FEATURES=""
if oc get namespace automl-demo &>/dev/null 2>&1; then
    DASHBOARD_FEATURES+="    AutoML:  Develop and train > AutoML\n"
fi
if oc get namespace autorag-demo &>/dev/null 2>&1; then
    DASHBOARD_FEATURES+="    AutoRAG: Develop and train > AutoRAG\n"
fi
if oc get namespace lmeval-demo &>/dev/null 2>&1; then
    DASHBOARD_FEATURES+="    EvalHub: Develop and train > Evaluations\n"
fi
if [ -n "$DASHBOARD_FEATURES" ]; then
    echo "  Dashboard-only features (no workbench needed):"
    echo -e "$DASHBOARD_FEATURES"
fi
