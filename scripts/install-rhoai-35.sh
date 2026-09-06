#!/bin/bash
################################################################################
# RHOAI 3.5 Installation Script
# Installs Red Hat OpenShift AI 3.5 with all prerequisites
#
# Key changes from 3.4:
#   - EvalHub now GA (SDK, CLI, MCP server, per-tenant deployment)
#   - External OIDC authentication for MaaS now GA (was TP in 3.4)
#   - Automated Red Teaming (Garak) now GA
#   - Responses API on OGX (formerly Llama Stack) now GA
#   - Priority-based flow control for llm-d now GA
#   - DiffusionGemma (dLLM) model support
#   - MLflow integration for AI Pipelines/Kubeflow Trainer/workbenches
#   - Kueue scheduling visibility in workbenches + self-managed ClusterQueues/LocalQueues
#   - GPU topology/utilization dashboard; canary rollout for KServe RawDeployment
#   - MaaS body-based model routing (OpenAI-compatible /v1/chat/completions)
#   - New TP: MCP gateway Operator, MCP Lifecycle Operator, MaaS multi-tenancy,
#     AutoGluon runtime, Docling SDK/Serve GPU images, llm-d batch inference
#
# Breaking changes to be aware of if upgrading from 3.4:
#   - llm-d flow control API group: inference.networking.x-k8s.io -> llm-d.ai
#   - llm-d metrics prefix: inference_extension_ -> llm_d_epp_
#   - llm-d tokenizer now runs as a dedicated external service (amd64 only)
#
# MaaS TLS (unchanged from 3.4):
#   - Uses OpenShift service-ca for Authorino TLS (NOT cert-manager Certificate)
#   - Gateway requires annotations: opendatahub.io/managed, authorino-tls-bootstrap
#   - Dashboard flags: observabilityDashboard, externalModels (new), toolCalling (new)
#   - CONFIRMED (live 3.5.0 cluster): `maasAuthPolicies` is REJECTED by 3.5's
#     OdhDashboardConfig CEL validation ("must be removed or left unchanged") —
#     do NOT set it on a fresh 3.5 install. Not called out in public release notes.
#   - Tenant CR auto-created in models-as-a-service namespace
#   - MaaS CRDs: MaaSSubscription, MaaSAuthPolicy, MaaSModelRef, Tenant, ExternalModel
#
# Reference: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5
################################################################################

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source utilities
source "$ROOT_DIR/lib/utils/colors.sh" 2>/dev/null || {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    NC='\033[0m'
}

# Default options
SKIP_PREREQUISITES=false
SKIP_RHCL=false
SKIP_MAAS=false
SKIP_NODE_SCALING=false
SKIP_MAAS_DB=false
ENABLE_LLMD=true
ENABLE_VLLM_MAAS=false
ENABLE_OBSERVABILITY=false
DEPLOY_GRAFANA=false
POSTGRES_CONNECTION=""
CLUSTER_DOMAIN=""
WAIT_TIMEOUT=600
RHOAI_CHANNEL=""
SETUP_PIPELINES=false
PIPELINE_NAMESPACE=""
SKIP_ADMIN_USER=false
CREATE_ADMIN_USER=""
SETUP_USERS=false
NUM_USERS=5
ADMIN_GROUP="rhods-admins"
USER_GROUP="rhods-users"
USER_PASSWORD="openshift"
ENABLE_EXTERNAL_MODELS=false
ENABLE_TOOL_CALLING=false

################################################################################
# Helper Functions
################################################################################

print_banner() {
    echo ""
    echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║          RHOAI 3.5 Installation Script                         ║${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${CYAN}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --skip-prerequisites    Skip installing NFD, GPU, Kueue, cert-manager operators"
    echo "  --skip-rhcl            Skip RHCL/Kuadrant installation (no MaaS/llm-d auth)"
    echo "  --skip-maas            Skip MaaS configuration"
    echo "  --skip-node-scaling    Skip automatic worker/GPU node scaling"
    echo "  --no-llmd              Don't configure llm-d Gateway"
    echo "  --enable-vllm-maas     Enable vLLM runtime for MaaS (Technology Preview)"
    echo "  --enable-observability Enable MaaS observability dashboard (Technology Preview)"
    echo "  --enable-external-models  Enable external model endpoints view (Technology Preview)"
    echo "  --enable-tool-calling  Enable validated tool-calling config display in Model Catalog"
    echo "  --deploy-grafana      Deploy standalone Grafana with GPU/vLLM dashboards"
    echo "  --postgres-connection <url>  External PostgreSQL for MaaS (skips POC DB deployment)"
    echo "                         Format: postgresql://user:pass@host:5432/db?sslmode=require"
    echo "  --skip-maas-db         Skip MaaS PostgreSQL setup entirely"
    echo "  --skip-admin-user      Skip creating the htpasswd admin user"
    echo "  --channel <channel>    RHOAI channel (e.g., stable-3.5, stable-3.x). If not specified, will prompt."
    echo "  --domain <domain>      Cluster domain (e.g., cluster.example.com)"
    echo "  --timeout <seconds>    Wait timeout for operators (default: 600)"
    echo ""
    echo "AI Pipelines:"
    echo "  --setup-pipelines      Deploy a pipeline server (DSPA) with built-in MinIO + MariaDB"
    echo "  --pipeline-namespace <ns>  Namespace for pipeline server (default: prompts interactively)"
    echo ""
    echo "User Management:"
    echo "  --setup-users          Create demo users (user1..userN) with htpasswd + groups"
    echo "  --num-users <N>        Number of demo users to create (default: 5, implies --setup-users)"
    echo "  --admin-group <name>   Admin group name (default: rhods-admins). user1 goes here."
    echo "  --user-group <name>    Regular user group name (default: rhods-users). user2+ go here."
    echo "  --user-password <pw>   Password for all demo users (default: openshift)"
    echo ""
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 --domain cluster.example.com"
    echo "  $0 --channel stable-3.5"
    echo "  $0 --channel stable-3.5 --enable-vllm-maas"
    echo "  $0 --channel stable-3.5 --enable-observability"
    echo "  $0 --postgres-connection 'postgresql://maas:secret@rds.example.com:5432/maas?sslmode=require'"
    echo "  $0 --setup-users --num-users 10 --user-password 'demo123'"
}

wait_for_operator() {
    local operator_name="$1"
    local namespace="$2"
    local timeout="${3:-$WAIT_TIMEOUT}"

    print_step "Waiting for $operator_name operator to be ready in $namespace..."

    local elapsed=0
    local interval=10
    local last_status=""

    while [ $elapsed -lt $timeout ]; do
        local csv_line=$(oc get csv -n "$namespace" 2>/dev/null | grep "$operator_name" | head -1)
        local status=$(echo "$csv_line" | awk '{print $NF}')
        local csv_name=$(echo "$csv_line" | awk '{print $1}')

        if [ "$status" = "Succeeded" ]; then
            print_success "$operator_name operator is ready ($csv_name)"
            return 0
        fi

        if [ -n "$status" ] && [ "$status" != "$last_status" ]; then
            echo "  $operator_name: $status ($csv_name) — ${elapsed}s elapsed"
            last_status="$status"
        elif [ -z "$csv_line" ] && [ $((elapsed % 30)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            echo "  $operator_name: CSV not yet created in $namespace — ${elapsed}s elapsed"
        fi

        sleep $interval
        elapsed=$((elapsed + interval))
    done

    print_error "$operator_name operator did not become ready within ${timeout}s"
    local final_csv=$(oc get csv -n "$namespace" 2>/dev/null | grep "$operator_name")
    [ -n "$final_csv" ] && print_info "  Last seen: $final_csv"
    return 1
}

wait_for_pod() {
    local label="$1"
    local namespace="$2"
    local timeout="${3:-300}"

    print_step "Waiting for pods with label $label..."

    local elapsed=0
    local interval=5

    while [ $elapsed -lt $timeout ]; do
        local ready=$(oc get pods -n "$namespace" -l "$label" -o jsonpath='{.items[*].status.containerStatuses[*].ready}' 2>/dev/null | grep -c "true" || echo "0")
        local total=$(oc get pods -n "$namespace" -l "$label" --no-headers 2>/dev/null | wc -l | tr -d ' ')

        if [ "$total" -gt 0 ] && [ "$ready" -eq "$total" ]; then
            print_success "Pods are ready"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    print_warning "Pods may not be fully ready"
    return 0
}

get_cluster_domain() {
    if [ -z "$CLUSTER_DOMAIN" ]; then
        CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null | sed 's/^apps\.//')
        if [ -z "$CLUSTER_DOMAIN" ]; then
            print_error "Could not detect cluster domain. Please specify with --domain"
            exit 1
        fi
    fi
    export CLUSTER_DOMAIN
    print_info "Cluster domain: $CLUSTER_DOMAIN"
}

################################################################################
# RHOAI Channel Selection
################################################################################

select_rhoai_channel() {
    print_step "Fetching available RHOAI channels from cluster..."

    local channels_raw=$(oc get packagemanifest rhods-operator -n openshift-marketplace \
        -o jsonpath='{.status.channels[*].name}' 2>/dev/null)

    if [ -z "$channels_raw" ]; then
        print_warning "Unable to fetch RHOAI channels from cluster"
        print_info "Using default channel: stable-3.5"
        RHOAI_CHANNEL="stable-3.5"
        return 0
    fi

    local default_channel=$(oc get packagemanifest rhods-operator -n openshift-marketplace \
        -o jsonpath='{.status.defaultChannel}' 2>/dev/null)

    local channels=()
    while IFS= read -r channel; do
        [ -n "$channel" ] && channels+=("$channel")
    done < <(echo "$channels_raw" | tr ' ' '\n' | sort -V)

    if [ ${#channels[@]} -eq 0 ]; then
        print_warning "No channels found, using default: stable-3.5"
        RHOAI_CHANNEL="stable-3.5"
        return 0
    fi

    echo ""
    echo -e "${CYAN}Available RHOAI Channels:${NC}"
    echo ""

    local stable_channels=()
    local fast_channels=()
    local other_channels=()

    for channel in "${channels[@]}"; do
        if [[ "$channel" == stable* ]]; then
            stable_channels+=("$channel")
        elif [[ "$channel" == fast* ]]; then
            fast_channels+=("$channel")
        else
            other_channels+=("$channel")
        fi
    done

    local idx=1
    local channel_map=()

    if [ ${#fast_channels[@]} -gt 0 ]; then
        echo -e "${MAGENTA}Fast Channels (Latest/Preview):${NC}"
        for channel in "${fast_channels[@]}"; do
            local marker=""
            [ "$channel" = "$default_channel" ] && marker=" ${GREEN}[default]${NC}"
            echo -e "  ${YELLOW}$idx)${NC} $channel$marker"
            channel_map+=("$channel")
            ((idx++))
        done
        echo ""
    fi

    if [ ${#stable_channels[@]} -gt 0 ]; then
        echo -e "${MAGENTA}Stable Channels:${NC}"
        for channel in "${stable_channels[@]}"; do
            local marker=""
            [ "$channel" = "$default_channel" ] && marker=" ${GREEN}[default]${NC}"
            echo -e "  ${YELLOW}$idx)${NC} $channel$marker"
            channel_map+=("$channel")
            ((idx++))
        done
        echo ""
    fi

    if [ ${#other_channels[@]} -gt 0 ]; then
        echo -e "${MAGENTA}Other Channels:${NC}"
        for channel in "${other_channels[@]}"; do
            local marker=""
            [ "$channel" = "$default_channel" ] && marker=" ${GREEN}[default]${NC}"
            echo -e "  ${YELLOW}$idx)${NC} $channel$marker"
            channel_map+=("$channel")
            ((idx++))
        done
        echo ""
    fi

    echo -e "${CYAN}Channel Types:${NC}"
    echo "  • stable-3.5 : RHOAI 3.5 GA (recommended for this script)"
    echo "  • stable-3.x : Rolling latest 3.x stream (currently resolves to 3.5.0)"
    echo "  • fast-3.x   : Fast-track channel (may lag behind stable-3.x — verify version before use)"
    echo "  • stable     : Production-ready releases (2.x lineage)"
    echo ""

    # Prefer stable-3.5 (this script targets 3.5 specifically). Fall back to the
    # cluster's own defaultChannel, then to fast-3.x only as a last resort.
    # NOTE: fast-3.x has been observed pointing to a stale/older CSV on some
    # clusters/catalogs, so it is intentionally de-prioritized here.
    local default_idx=1
    for i in "${!channel_map[@]}"; do
        if [ "${channel_map[$i]}" = "stable-3.5" ]; then
            default_idx=$((i + 1))
            break
        elif [ "${channel_map[$i]}" = "$default_channel" ]; then
            default_idx=$((i + 1))
        elif [ "${channel_map[$i]}" = "fast-3.x" ] && [ "$default_idx" -eq 1 ]; then
            default_idx=$((i + 1))
        fi
    done

    local max_idx=${#channel_map[@]}
    local choice=""

    while true; do
        read -p "Select channel (1-$max_idx) [default: $default_idx - ${channel_map[$((default_idx - 1))]}]: " choice
        choice=$(echo "$choice" | tr -d '[:space:]')

        if [ -z "$choice" ]; then
            choice=$default_idx
            break
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$max_idx" ]; then
            break
        else
            print_error "Invalid selection. Please enter a number between 1 and $max_idx"
        fi
    done

    RHOAI_CHANNEL="${channel_map[$((choice - 1))]}"
    print_success "Selected channel: $RHOAI_CHANNEL"
}

################################################################################
# Installation Functions
################################################################################

check_prerequisites() {
    print_step "Checking prerequisites..."

    if ! command -v oc &> /dev/null; then
        print_error "oc CLI not found. Please install OpenShift CLI."
        exit 1
    fi

    if ! oc whoami &> /dev/null; then
        print_error "Not logged in to OpenShift cluster. Please run 'oc login' first."
        exit 1
    fi

    if ! oc auth can-i create clusterrole &> /dev/null; then
        print_error "You need cluster-admin privileges to install RHOAI."
        exit 1
    fi

    local ocp_version=$(oc version -o json 2>/dev/null | jq -r '.openshiftVersion' | cut -d. -f1,2)
    print_info "OpenShift version: $ocp_version"

    if [[ "$ocp_version" < "4.19" ]]; then
        print_error "RHOAI 3.5 requires OpenShift 4.19 or later. Current: $ocp_version"
        exit 1
    fi

    if [ "$ENABLE_LLMD" = true ] && [[ "$ocp_version" < "4.20" ]]; then
        print_warning "Distributed inference with llm-d requires OCP 4.20+. Current: $ocp_version"
        print_warning "llm-d will be installed but multi-node inference may not work correctly."
    fi

    if [[ "$ocp_version" > "4.20" ]]; then
        print_info "Note: RHOAI 3.5 documentation lists OCP 4.19-4.20 as the validated range."
        print_info "OCP $ocp_version is newer than that range; installation will proceed but is outside the documented support matrix."
    fi

    print_success "Prerequisites check passed"
}

################################################################################
# Admin User Creation
################################################################################

wait_for_api_server() {
    local max_wait=${1:-120}
    local elapsed=0
    local interval=5
    while [ $elapsed -lt $max_wait ]; do
        if oc get nodes &>/dev/null; then
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        echo "  Waiting for API server... (${elapsed}s/${max_wait}s)"
    done
    print_warning "API server did not respond within ${max_wait}s"
    return 1
}

# Retry a command up to N times with API server recovery between attempts
retry_with_api_wait() {
    local max_retries=${1:-3}
    shift
    local attempt=1
    while [ $attempt -le $max_retries ]; do
        if "$@" 2>/dev/null; then
            return 0
        fi
        print_warning "Command failed (attempt $attempt/$max_retries), waiting for API server..."
        wait_for_api_server 60
        attempt=$((attempt + 1))
    done
    print_error "Command failed after $max_retries attempts: $*"
    return 1
}

recover_router_if_crashlooping() {
    local router_status
    router_status=$(oc get pods -n openshift-ingress -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default \
        -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)

    if [ "$router_status" = "CrashLoopBackOff" ]; then
        print_warning "Router pod is in CrashLoopBackOff (caused by API server restart)"
        print_step "Deleting stuck router pod to reset backoff..."
        oc delete pod -n openshift-ingress \
            -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default \
            --wait=false 2>/dev/null || true
        sleep 10
        local new_status
        new_status=$(oc get pods -n openshift-ingress \
            -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default \
            -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)
        if [ "$new_status" = "Running" ]; then
            print_success "Router pod recovered"
        else
            print_info "Router pod restarting (status: $new_status) — it should recover shortly"
        fi
    fi
}

create_admin_user() {
    local admin_user="admin"
    local admin_pass='R3dh4t1!'

    # Check if admin user already exists in htpasswd
    local admin_exists=false
    if oc get secret htpasswd-secret -n openshift-config &>/dev/null; then
        if oc get secret htpasswd-secret -n openshift-config \
            -o jsonpath='{.data.htpasswd}' 2>/dev/null | base64 -d 2>/dev/null | grep -q "^${admin_user}:"; then
            admin_exists=true
        fi
    fi

    if [ "$admin_exists" = true ]; then
        print_info "Admin user '$admin_user' already exists — skipping creation"
        # Ensure group membership is correct even if user already exists
        if ! oc get group "$ADMIN_GROUP" &>/dev/null 2>&1; then
            oc adm groups new "$ADMIN_GROUP" 2>/dev/null || true
        fi
        oc adm groups add-users "$ADMIN_GROUP" "$admin_user" 2>/dev/null || true
        return 0
    fi

    print_step "Creating OAuth admin user '$admin_user'..."

    if ! command -v htpasswd &>/dev/null; then
        print_error "htpasswd CLI not found. Install httpd-tools (RHEL) or apache2-utils (Debian)."
        return 1
    fi

    # Pull existing htpasswd data (preserve other users)
    local htpasswd_tmp
    htpasswd_tmp=$(mktemp)

    if oc get secret htpasswd-secret -n openshift-config &>/dev/null; then
        oc get secret htpasswd-secret -n openshift-config \
            -o jsonpath='{.data.htpasswd}' | base64 -d > "$htpasswd_tmp" 2>/dev/null || true
    fi

    htpasswd -bB "$htpasswd_tmp" "$admin_user" "$admin_pass"
    print_success "User '$admin_user' added to htpasswd"

    # Update secret
    oc create secret generic htpasswd-secret \
        --from-file=htpasswd="$htpasswd_tmp" \
        -n openshift-config --dry-run=client -o yaml | oc apply -f -
    rm -f "$htpasswd_tmp"

    # Ensure htpasswd identity provider is configured
    local has_htpasswd
    has_htpasswd=$(oc get oauth cluster -o jsonpath='{.spec.identityProviders[?(@.name=="htpasswd")].name}' 2>/dev/null || true)
    if [ -z "$has_htpasswd" ]; then
        print_step "Adding htpasswd identity provider to OAuth..."
        oc patch oauth cluster --type=json -p '[{
            "op": "add",
            "path": "/spec/identityProviders/-",
            "value": {
                "name": "htpasswd",
                "type": "HTPasswd",
                "mappingMethod": "claim",
                "htpasswd": {
                    "fileData": {
                        "name": "htpasswd-secret"
                    }
                }
            }
        }]' 2>/dev/null || {
            oc patch oauth cluster --type=merge -p '{
                "spec": {
                    "identityProviders": [{
                        "name": "htpasswd",
                        "type": "HTPasswd",
                        "mappingMethod": "claim",
                        "htpasswd": {
                            "fileData": {
                                "name": "htpasswd-secret"
                            }
                        }
                    }]
                }
            }' 2>/dev/null
        }
        print_success "htpasswd identity provider configured"
    else
        print_info "htpasswd identity provider already configured"
    fi

    # Grant cluster-admin
    oc adm policy add-cluster-role-to-user cluster-admin "$admin_user" 2>/dev/null || true
    print_success "cluster-admin granted to '$admin_user'"

    # Create rhods-admins group and add admin
    if ! oc get group "$ADMIN_GROUP" &>/dev/null 2>&1; then
        oc adm groups new "$ADMIN_GROUP" 2>/dev/null || true
    fi
    oc adm groups add-users "$ADMIN_GROUP" "$admin_user" 2>/dev/null || true
    print_info "User '$admin_user' added to group '$ADMIN_GROUP'"

    # Don't switch sessions — continue using kube:admin for stability
    # The OAuth config change triggers an API server rollout; avoid disruption
    # by staying on the current session. User can log in as 'admin' later.
    print_success "Admin user created. Continuing installation as $(oc whoami)"
    print_info "Log in as '$admin_user' after installation: oc login -u $admin_user -p '$admin_pass'"
    echo ""

    # Wait briefly for the OAuth rollout to settle, then recover router if needed
    print_step "Waiting for API server to stabilize after OAuth change..."
    sleep 10
    wait_for_api_server 90
    recover_router_if_crashlooping
    print_success "Cluster stable — continuing installation"
}

scale_cluster_nodes() {
    print_step "Checking and scaling cluster nodes..."

    local worker_ms=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io/cluster-api-machine-role=="worker")].metadata.name}' 2>/dev/null | awk '{print $1}')

    if [ -z "$worker_ms" ]; then
        print_warning "No worker machineset found, skipping node scaling"
        return 0
    fi

    local current_replicas=$(oc get machineset "$worker_ms" -n openshift-machine-api -o jsonpath='{.spec.replicas}' 2>/dev/null)
    print_info "Worker machineset: $worker_ms (current replicas: $current_replicas)"

    if [ "$current_replicas" -lt 2 ]; then
        print_step "Scaling worker nodes to 2..."
        oc scale machineset "$worker_ms" -n openshift-machine-api --replicas=2
        print_success "Worker machineset scaled to 2 replicas"
    else
        print_info "Worker nodes already at $current_replicas replicas"
    fi

    local gpu_ms=$(oc get machineset -n openshift-machine-api -o name 2>/dev/null | grep -i gpu | head -1)

    if [ -n "$gpu_ms" ]; then
        print_info "GPU machineset already exists: $gpu_ms"
        local gpu_replicas=$(oc get "$gpu_ms" -n openshift-machine-api -o jsonpath='{.spec.replicas}' 2>/dev/null)
        if [ "$gpu_replicas" -eq 0 ]; then
            print_step "Scaling GPU machineset to 1..."
            oc scale "$gpu_ms" -n openshift-machine-api --replicas=1
            print_success "GPU machineset scaled to 1 replica"
        fi
    else
        print_step "Creating GPU machineset..."
        if [ -f "$ROOT_DIR/scripts/create-gpu-machineset.sh" ]; then
            local az=$(oc get machineset "$worker_ms" -n openshift-machine-api -o jsonpath='{.spec.template.spec.providerSpec.value.placement.availabilityZone}' 2>/dev/null)
            "$ROOT_DIR/scripts/create-gpu-machineset.sh" --instance-type g6e.xlarge --az "$az" --replicas 1 --apply
            print_success "GPU machineset created and scaled to 1 replica"
        else
            print_warning "GPU machineset script not found, skipping GPU node creation"
        fi
    fi

    print_info "Nodes are scaling in the background. Installation will continue."
    print_info "Check node status with: oc get nodes"
}

install_nfd_operator() {
    print_step "Installing Node Feature Discovery (NFD) Operator..."

    if oc get csv -n openshift-nfd 2>/dev/null | grep -q nfd; then
        print_info "NFD Operator already installed"
        return 0
    fi

    oc create namespace openshift-nfd 2>/dev/null || true

    local og_count=$(oc get operatorgroup -n openshift-nfd -o name 2>/dev/null | wc -l | tr -d ' ')
    if [ "$og_count" -gt 0 ]; then
        print_info "Found $og_count existing OperatorGroup(s) in openshift-nfd namespace"
        oc delete operatorgroup --all -n openshift-nfd 2>/dev/null || true
        sleep 2
    fi

    oc apply -f "$ROOT_DIR/lib/manifests/operators/nfd-operator.yaml"
    wait_for_operator "nfd" "openshift-nfd"

    print_step "Creating NFD instance..."
    oc apply -f "$ROOT_DIR/lib/manifests/operators/nfd-instance.yaml"

    print_success "NFD Operator installed"
}

install_gpu_operator() {
    print_step "Installing NVIDIA GPU Operator..."

    if oc get csv -n nvidia-gpu-operator 2>/dev/null | grep -q gpu-operator; then
        print_info "GPU Operator already installed"
        return 0
    fi

    oc create namespace nvidia-gpu-operator 2>/dev/null || true

    local og_count=$(oc get operatorgroup -n nvidia-gpu-operator -o name 2>/dev/null | wc -l | tr -d ' ')
    if [ "$og_count" -gt 0 ]; then
        print_info "Found $og_count existing OperatorGroup(s) in nvidia-gpu-operator namespace"
        oc delete operatorgroup --all -n nvidia-gpu-operator 2>/dev/null || true
        sleep 2
    fi

    oc apply -f "$ROOT_DIR/lib/manifests/operators/gpu-operator.yaml"
    wait_for_operator "gpu-operator" "nvidia-gpu-operator"

    print_step "Creating ClusterPolicy..."
    oc apply -f "$ROOT_DIR/lib/manifests/operators/gpu-clusterpolicy.yaml"

    print_success "GPU Operator installed"
}

install_kueue_operator() {
    print_step "Installing Red Hat Build of Kueue Operator..."

    if oc get csv -n openshift-operators 2>/dev/null | grep -q kueue; then
        print_info "Kueue Operator already installed"
        return 0
    fi

    oc apply -f "$ROOT_DIR/lib/manifests/operators/kueue-subscription.yaml"
    wait_for_operator "kueue" "openshift-operators"

    print_success "Kueue Operator installed"
}

install_certmanager_operator() {
    print_step "Installing cert-manager Operator..."

    if oc get csv -n cert-manager-operator 2>/dev/null | grep -q cert-manager; then
        print_info "cert-manager Operator already installed"
        return 0
    fi

    oc create namespace cert-manager-operator 2>/dev/null || true

    local og_count=$(oc get operatorgroup -n cert-manager-operator -o name 2>/dev/null | wc -l | tr -d ' ')
    if [ "$og_count" -gt 0 ]; then
        print_info "Found $og_count existing OperatorGroup(s) in cert-manager-operator namespace"
        oc delete operatorgroup --all -n cert-manager-operator 2>/dev/null || true
        sleep 2
    fi

    oc apply -f "$ROOT_DIR/lib/manifests/operators/certmanager-operatorgroup.yaml"
    oc apply -f "$ROOT_DIR/lib/manifests/operators/certmanager-subscription.yaml"
    wait_for_operator "cert-manager" "cert-manager-operator"

    print_success "cert-manager Operator installed"
}

install_lws_operator() {
    print_step "Installing Leader Worker Set (LWS) Operator..."

    if oc get csv -n openshift-lws-operator 2>/dev/null | grep -q "leader-worker-set"; then
        print_info "LWS Operator already installed"
        return 0
    fi

    oc create namespace openshift-lws-operator 2>/dev/null || true

    local og_count=$(oc get operatorgroup -n openshift-lws-operator -o name 2>/dev/null | wc -l | tr -d ' ')
    if [ "$og_count" -gt 0 ]; then
        print_info "Found $og_count existing OperatorGroup(s) in openshift-lws-operator namespace"
        oc delete operatorgroup --all -n openshift-lws-operator 2>/dev/null || true
        sleep 2
    fi

    oc apply -f "$ROOT_DIR/lib/manifests/operators/lws-operatorgroup.yaml"
    oc apply -f "$ROOT_DIR/lib/manifests/operators/lws-subscription.yaml"
    wait_for_operator "leader-worker-set" "openshift-lws-operator"

    oc apply -f "$ROOT_DIR/lib/manifests/operators/lws-operator-cr.yaml"

    print_success "LWS Operator installed"
}

install_servicemesh_operator() {
    print_step "Installing OpenShift Service Mesh 3 Operator..."

    if oc get csv -n openshift-operators 2>/dev/null | grep -q "servicemeshoperator3.*Succeeded"; then
        print_info "Service Mesh 3 Operator already installed and ready"
    else
        if ! oc get subscription servicemeshoperator3 -n openshift-operators &>/dev/null; then
            oc apply -f "$ROOT_DIR/lib/manifests/operators/servicemesh3-subscription.yaml"
        fi

        print_step "Waiting for Service Mesh InstallPlan to be created..."
        local ip_wait=0
        local ip_timeout=60
        while [ $ip_wait -lt $ip_timeout ]; do
            local has_plan=$(oc get installplan -n openshift-operators -o json 2>/dev/null | \
                jq -r '[.items[] | select(.spec.approved == false) | select(.spec.clusterServiceVersionNames[] | test("servicemesh|kiali"))] | length' 2>/dev/null)
            if [ -n "$has_plan" ] && [ "$has_plan" -gt 0 ]; then
                print_info "Found pending InstallPlan(s)"
                break
            fi
            sleep 5
            ip_wait=$((ip_wait + 5))
        done

        approve_servicemesh_installplans

        print_step "Waiting for Service Mesh operator to be ready..."
        local timeout=300
        local elapsed=0
        until oc get csv -n openshift-operators 2>/dev/null | grep -q "servicemeshoperator3.*Succeeded"; do
            if [ $elapsed -ge $timeout ]; then
                print_warning "Service Mesh operator not ready after ${timeout}s (continuing anyway)"
                break
            fi
            approve_servicemesh_installplans 2>/dev/null || true
            sleep 10
            elapsed=$((elapsed + 10))
        done
    fi

    approve_servicemesh_installplans 2>/dev/null || true

    print_success "Service Mesh 3 Operator installed"
}

approve_servicemesh_installplans() {
    local approved_any=false

    local all_pending=$(oc get installplan -n openshift-operators --no-headers 2>/dev/null | awk '{print $1}')
    for plan in $all_pending; do
        local is_approved=$(oc get installplan "$plan" -n openshift-operators -o jsonpath='{.spec.approved}' 2>/dev/null)
        if [ "$is_approved" = "false" ]; then
            local csv_names=$(oc get installplan "$plan" -n openshift-operators -o jsonpath='{.spec.clusterServiceVersionNames[*]}' 2>/dev/null)
            if echo "$csv_names" | grep -qiE "servicemesh|kiali|sail"; then
                print_step "Approving InstallPlan: $plan (CSVs: $csv_names)"
                oc patch installplan "$plan" -n openshift-operators --type merge -p '{"spec":{"approved":true}}'
                print_success "Approved InstallPlan: $plan"
                approved_any=true
            fi
        fi
    done

    if [ "$approved_any" = true ]; then
        sleep 10
    fi
}

approve_rhcl_installplans() {
    local all_pending=$(oc get installplan -n openshift-operators --no-headers 2>/dev/null | awk '{print $1}')
    for plan in $all_pending; do
        local is_approved=$(oc get installplan "$plan" -n openshift-operators -o jsonpath='{.spec.approved}' 2>/dev/null)
        if [ "$is_approved" = "false" ]; then
            local csv_names=$(oc get installplan "$plan" -n openshift-operators -o jsonpath='{.spec.clusterServiceVersionNames[*]}' 2>/dev/null)
            if echo "$csv_names" | grep -qiE "rhcl|authorino|limitador|dns-operator"; then
                print_step "Approving RHCL InstallPlan: $plan"
                print_info "  CSVs: $csv_names"
                oc patch installplan "$plan" -n openshift-operators --type merge -p '{"spec":{"approved":true}}'
                print_success "Approved InstallPlan: $plan"
            fi
        fi
    done
}

setup_istio_for_kuadrant() {
    print_step "Setting up Istio for Kuadrant..."

    oc create namespace istio-system 2>/dev/null || true
    oc create namespace istio-cni 2>/dev/null || true

    if oc get istio default -n istio-system &>/dev/null; then
        print_info "Istio instance already exists in istio-system"
    else
        local istio_version=$(oc get istio -A -o jsonpath='{.items[0].spec.version}' 2>/dev/null || echo "v1.30.1")

        print_step "Creating IstioCNI..."
        export ISTIO_VERSION="$istio_version"
        envsubst '${ISTIO_VERSION}' < "$ROOT_DIR/lib/manifests/rhcl/istiocni.yaml" | oc apply -f -

        print_step "Waiting for IstioCNI to be ready..."
        local elapsed=0
        local timeout=120
        while [ $elapsed -lt $timeout ]; do
            local cni_ready=$(oc get istiocni default -n istio-cni -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
            if [ "$cni_ready" = "True" ]; then
                print_success "IstioCNI is ready"
                break
            fi
            sleep 10
            elapsed=$((elapsed + 10))
            echo "  Waiting for IstioCNI... (${elapsed}s elapsed)"
        done

        print_step "Creating Istio instance in istio-system..."
        envsubst '${ISTIO_VERSION}' < "$ROOT_DIR/lib/manifests/rhcl/istio.yaml" | oc apply -f -

        print_step "Waiting for Istio to be healthy..."
        elapsed=0
        timeout=180
        while [ $elapsed -lt $timeout ]; do
            local istio_status=$(oc get istio default -n istio-system -o jsonpath='{.status.state}' 2>/dev/null)
            if [ "$istio_status" = "Healthy" ]; then
                print_success "Istio is healthy"
                break
            fi
            sleep 10
            elapsed=$((elapsed + 10))
            echo "  Waiting for Istio... Status: $istio_status (${elapsed}s elapsed)"
        done
    fi

    # API server may bounce during Istio/Sail webhook registration
    wait_for_api_server 90

    # Fix OCP ingress operator if its ISTIO_VERSION doesn't match a supported version.
    # OCP 4.20 ships with ISTIO_VERSION=v1.26.2 which is EOL in Service Mesh 3.4.0+.
    # The ingress operator creates Istio CRs for GatewayClasses, so the version must be valid.
    local ingress_istio_ver
    ingress_istio_ver=$(oc get deployment ingress-operator -n openshift-ingress-operator \
        -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ISTIO_VERSION")].value}' 2>/dev/null)
    if [ -n "$ingress_istio_ver" ]; then
        local istio_version_needed
        istio_version_needed=$(oc get istio -A -o jsonpath='{.items[0].spec.version}' 2>/dev/null || echo "v1.30.1")
        if [ "$ingress_istio_ver" != "$istio_version_needed" ]; then
            # Check if the ingress operator's version is actually supported by the SM operator
            local sm_pod
            sm_pod=$(oc get pods -n openshift-operators --no-headers 2>/dev/null | grep servicemesh-operator | head -1 | awk '{print $1}')
            if [ -n "$sm_pod" ]; then
                local supported_versions
                supported_versions=$(oc logs "$sm_pod" -n openshift-operators 2>/dev/null \
                    | grep "config loaded" | grep -oE '"v[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | sort -u)
                if [ -n "$supported_versions" ] && ! echo "$supported_versions" | grep -q "^${ingress_istio_ver}$"; then
                    print_warning "OCP ingress operator has ISTIO_VERSION=$ingress_istio_ver (unsupported by SM operator)"
                    print_step "Patching ingress operator to ISTIO_VERSION=$istio_version_needed..."
                    oc set env deployment/ingress-operator -n openshift-ingress-operator \
                        ISTIO_VERSION="$istio_version_needed" 2>/dev/null
                    print_success "Ingress operator patched"
                    sleep 10
                fi
            fi
        fi
    fi

    if ! oc get gatewayclass openshift-default &>/dev/null; then
        print_step "Creating openshift-default GatewayClass..."
        local attempt=1
        while [ $attempt -le 3 ]; do
            if oc apply -f "$ROOT_DIR/lib/manifests/rhcl/gatewayclass-default.yaml"; then
                break
            fi
            print_warning "GatewayClass creation failed (attempt $attempt/3), waiting for API server..."
            wait_for_api_server 60
            attempt=$((attempt + 1))
        done
    fi

    print_success "Istio setup complete for Kuadrant"
}

restart_kuadrant_operator() {
    print_step "Restarting Kuadrant operator to detect Istio..."

    local pod_name=$(oc get pods -n kuadrant-system -o name 2>/dev/null | grep kuadrant-operator-controller)
    if [ -n "$pod_name" ]; then
        oc delete $pod_name -n kuadrant-system 2>/dev/null || true
        sleep 20
    fi

    print_step "Waiting for Kuadrant to be ready..."
    local elapsed=0
    local timeout=120
    while [ $elapsed -lt $timeout ]; do
        local kuadrant_ready=$(oc get kuadrant kuadrant -n kuadrant-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        local kuadrant_reason=$(oc get kuadrant kuadrant -n kuadrant-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null)

        if [ "$kuadrant_ready" = "True" ]; then
            print_success "Kuadrant is ready"
            return 0
        fi

        sleep 10
        elapsed=$((elapsed + 10))
        echo "  Waiting for Kuadrant... Reason: $kuadrant_reason (${elapsed}s elapsed)"
    done

    print_warning "Kuadrant may not be fully ready. Check: oc get kuadrant -n kuadrant-system"
}

install_rhcl_operator() {
    # RHOAI 3.4+ MaaS prerequisite (Govern LLM access with Models-as-a-Service, §1.2):
    #   "installed the Red Hat Connectivity Link Operator version 1.2 or later
    #    to the openshift-operators namespace and created a Kuadrant custom resource
    #    in the kuadrant-system namespace with ready status."
    # This RHCL v1.2+ requirement is unchanged in RHOAI 3.5 — no 3.5-specific RHCL
    # manifest is needed, so we reuse the same rhcl-operator-34.yaml subscription below.
    #
    # Note: RHCL 1.3's own docs put everything in kuadrant-system. Both patterns work
    # (AllNamespaces mode). We follow RHOAI's documented prerequisite since this is an RHOAI toolkit.
    #
    # Service Mesh 3 (Sail) is auto-installed as an OLM dependency. It uses Manual InstallPlan
    # approval, so we must ensure plans are approved.
    print_step "Installing Red Hat Connectivity Link (RHCL) v1.2+ Operator..."

    # Service Mesh 3 comes in as an OLM dependency — ensure it's installed and plans approved
    install_servicemesh_operator

    # Check if RHCL already installed
    if oc get csv -n openshift-operators 2>/dev/null | grep -q "rhcl-operator"; then
        print_info "RHCL Operator already installed in openshift-operators"
    elif oc get csv -n kuadrant-system 2>/dev/null | grep -q "rhcl-operator"; then
        print_info "RHCL Operator already installed in kuadrant-system"
    else
        # Subscription goes to openshift-operators (per RHOAI 3.4+ MaaS docs, unchanged in 3.5)
        # openshift-operators already has a default OperatorGroup — no need to create one
        oc apply -f "$ROOT_DIR/lib/manifests/rhcl/rhcl-operator-34.yaml"

        # Wait for Subscription to create an InstallPlan
        print_step "Waiting for RHCL InstallPlan..."
        local ip_wait=0
        while [ $ip_wait -lt 60 ]; do
            if oc get subscription rhcl-operator -n openshift-operators \
                -o jsonpath='{.status.installPlanRef.name}' &>/dev/null; then
                break
            fi
            sleep 5
            ip_wait=$((ip_wait + 5))
        done

        # Auto-approve RHCL InstallPlan (OLM may set Manual even with Automatic
        # when dependency operators like Authorino/DNS/Limitador are being upgraded)
        approve_rhcl_installplans

        # Wait for operator with periodic re-approval (InstallPlan may appear late)
        print_step "Waiting for rhcl-operator to be ready..."
        local rhcl_elapsed=0
        local rhcl_timeout=300
        while [ $rhcl_elapsed -lt $rhcl_timeout ]; do
            local rhcl_csv=$(oc get csv -n openshift-operators 2>/dev/null | grep "rhcl-operator" | head -1)
            local rhcl_status=$(echo "$rhcl_csv" | awk '{print $NF}')
            
            if [ "$rhcl_status" = "Succeeded" ]; then
                print_success "rhcl-operator is ready"
                break
            fi
            
            # Re-approve any pending InstallPlans on each iteration
            approve_rhcl_installplans 2>/dev/null || true
            
            if [ -z "$rhcl_csv" ] && [ $((rhcl_elapsed % 30)) -eq 0 ] && [ $rhcl_elapsed -gt 0 ]; then
                echo "  rhcl-operator: CSV not yet created — ${rhcl_elapsed}s elapsed"
            elif [ -n "$rhcl_status" ] && [ "$rhcl_status" != "Succeeded" ]; then
                echo "  rhcl-operator: $rhcl_status — ${rhcl_elapsed}s elapsed"
            fi
            
            sleep 10
            rhcl_elapsed=$((rhcl_elapsed + 10))
        done
        
        if [ $rhcl_elapsed -ge $rhcl_timeout ]; then
            print_warning "rhcl-operator may not be fully ready (continuing)"
        fi
    fi

    # Verify RHCL component operators (Authorino, DNS, Limitador)
    # These are installed by the RHCL operator as dependencies
    print_step "Verifying RHCL component operators..."
    local comp_timeout=120
    local comp_elapsed=0
    local all_found=false
    while [ $comp_elapsed -lt $comp_timeout ]; do
        all_found=true
        for component in "authorino" "dns" "limitador"; do
            if ! oc get csv -n openshift-operators 2>/dev/null | grep -qi "$component.*Succeeded"; then
                all_found=false
                break
            fi
        done
        if [ "$all_found" = true ]; then
            break
        fi
        sleep 10
        comp_elapsed=$((comp_elapsed + 10))
    done

    for component in "authorino" "dns" "limitador"; do
        if oc get csv -n openshift-operators 2>/dev/null | grep -qi "$component.*Succeeded"; then
            print_success "  $component operator ready"
        else
            print_info "  $component operator not yet ready (may take a moment)"
        fi
    done

    # Kuadrant CR goes in kuadrant-system (per RHOAI 3.4+ MaaS docs, unchanged in 3.5)
    oc create namespace kuadrant-system 2>/dev/null || true

    print_step "Creating Kuadrant instance in kuadrant-system..."
    oc apply -f "$ROOT_DIR/lib/manifests/rhcl/kuadrant-instance.yaml"

    setup_istio_for_kuadrant

    restart_kuadrant_operator

    print_success "RHCL Operator installed and configured"
}

setup_maas_database() {
    # PostgreSQL 14+ is required for MaaS API key validation
    # Secret format: DB_CONNECTION_URL='postgresql://user:pass@host:5432/db?sslmode=require'
    # Reference: https://opendatahub-io.github.io/models-as-a-service/latest/install/maas-setup/#database-setup
    print_step "Setting up MaaS PostgreSQL database..."

    if oc get secret maas-db-config -n redhat-ods-applications &>/dev/null; then
        print_success "maas-db-config secret already exists in redhat-ods-applications"
        return 0
    fi

    # If user provided a connection string via --postgres-connection, use it
    if [ -n "$POSTGRES_CONNECTION" ]; then
        print_step "Creating maas-db-config secret from provided connection string..."
        printf '%s' "$POSTGRES_CONNECTION" | \
            oc create secret generic maas-db-config \
                --from-file=DB_CONNECTION_URL=/dev/stdin \
                --dry-run=client -o yaml | \
            oc label --local -f - app=maas-api --dry-run=client -o yaml | \
            oc apply -n redhat-ods-applications -f -
        print_success "maas-db-config secret created from provided connection string"
        return 0
    fi

    # Deploy a POC-grade PostgreSQL instance (NOT for production)
    print_warning "No --postgres-connection provided. Deploying POC PostgreSQL (NOT for production)."
    print_info "For production, use AWS RDS, Crunchy Operator, or Azure Database for PostgreSQL."
    print_info "Then pass: --postgres-connection 'postgresql://user:pass@host:5432/db?sslmode=require'"
    echo ""

    local pg_user="maas"
    local pg_db="maas"
    local pg_password
    pg_password="$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)"

    # Resolve PostgreSQL image from RHOAI operator CSV (fallback to default)
    local pg_image
    pg_image=$(oc get csv -l 'olm.copiedFrom=redhat-ods-operator' \
        -o jsonpath='{.items[0].spec.relatedImages[?(@.name=="postgresql_16_image")].image}' 2>/dev/null) || true
    if [ -z "$pg_image" ]; then
        pg_image="registry.redhat.io/rhel9/postgresql-16:latest"
        print_info "Using default PostgreSQL image (operator CSV not available)"
    else
        print_info "Resolved PostgreSQL image from operator CSV"
    fi

    print_step "Deploying POC PostgreSQL in redhat-ods-applications..."
    oc apply -n redhat-ods-applications -f "$ROOT_DIR/lib/manifests/maas/postgres-pvc.yaml"
    oc apply -n redhat-ods-applications -f "$ROOT_DIR/lib/manifests/maas/postgres-service.yaml"

    export PG_IMAGE="$pg_image"
    export PG_USER="$pg_user"
    export PG_PASSWORD="$pg_password"
    export PG_DB="$pg_db"
    envsubst '${PG_IMAGE} ${PG_USER} ${PG_PASSWORD} ${PG_DB}' \
        < "$ROOT_DIR/lib/manifests/maas/postgres-deployment.yaml" | oc apply -n redhat-ods-applications -f -
    unset PG_PASSWORD

    print_step "Waiting for PostgreSQL to be ready..."
    local elapsed=0
    while [ $elapsed -lt 120 ]; do
        if oc rollout status deployment/postgres -n redhat-ods-applications --timeout=5s &>/dev/null; then
            print_success "PostgreSQL is ready"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    # URL-encode the password (encode all chars to be safe with special chars)
    local encoded_password
    encoded_password=$(printf '%s' "$pg_password" | od -An -tx1 | tr -d ' \n' | sed 's/../%&/g')
    local db_url="postgresql://${pg_user}:${encoded_password}@postgres:5432/${pg_db}?sslmode=disable"

    print_step "Creating maas-db-config secret..."
    printf '%s' "$db_url" | \
        oc create secret generic maas-db-config \
            --from-file=DB_CONNECTION_URL=/dev/stdin \
            --dry-run=client -o yaml | \
        oc label --local -f - app=maas-api --dry-run=client -o yaml | \
        oc apply -n redhat-ods-applications -f -

    # Store credentials for reference
    oc create secret generic postgres-creds \
        --from-literal=user="$pg_user" \
        --from-literal=password="$pg_password" \
        --from-literal=database="$pg_db" \
        -n redhat-ods-applications --dry-run=client -o yaml | \
        oc apply -n redhat-ods-applications -f -

    print_success "POC PostgreSQL deployed and maas-db-config secret created"
    print_warning "This is NOT production-grade. For production use:"
    print_info "  - AWS RDS for PostgreSQL"
    print_info "  - Crunchy Postgres Operator"
    print_info "  - Azure Database for PostgreSQL"
    print_info "  Then: oc create secret generic maas-db-config \\"
    print_info "    --from-literal=DB_CONNECTION_URL='postgresql://user:pass@host:5432/db?sslmode=require' \\"
    print_info "    -n redhat-ods-applications"
}

configure_maas_tls() {
    # RHOAI 3.4+ MaaS TLS uses OpenShift service-ca (NOT cert-manager) — unchanged in 3.5
    # Reference: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/govern_llm_access_with_models-as-a-service/deploy-and-manage-models-as-a-service_maas#configure-tls-for-maas_maas-deploy
    print_step "Configuring TLS for Models-as-a-Service (3.4+ service-ca method)..."

    # Step 1: Annotate Authorino service for OpenShift service-ca cert generation
    print_step "Annotating Authorino service for service-ca TLS cert..."
    oc annotate service authorino-authorino-authorization \
        -n kuadrant-system \
        service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert \
        --overwrite 2>/dev/null || {
        print_warning "Could not annotate Authorino service - it may not exist yet"
        return 1
    }

    # Wait for the service-ca operator to generate the TLS secret
    print_step "Waiting for service-ca to generate authorino-server-cert secret..."
    local cert_wait=0
    while [ $cert_wait -lt 60 ]; do
        if oc get secret authorino-server-cert -n kuadrant-system &>/dev/null; then
            print_success "Authorino TLS certificate generated by service-ca"
            break
        fi
        sleep 5
        cert_wait=$((cert_wait + 5))
    done

    if ! oc get secret authorino-server-cert -n kuadrant-system &>/dev/null; then
        print_warning "authorino-server-cert secret not yet available - service-ca may need more time"
    fi

    # Step 2: Patch Authorino CR to enable TLS listener
    print_step "Patching Authorino CR for TLS listener..."
    oc patch authorino authorino -n kuadrant-system --type=merge --patch '{
      "spec": {
        "listener": {
          "tls": {
            "enabled": true,
            "certSecretRef": {
              "name": "authorino-server-cert"
            }
          }
        }
      }
    }' 2>/dev/null || print_warning "Could not patch Authorino CR"

    # Step 3: Set TLS cert env vars on Authorino deployment for CA validation
    print_step "Configuring Authorino TLS certificate validation env vars..."
    oc -n kuadrant-system set env deployment/authorino \
        SSL_CERT_FILE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt \
        REQUESTS_CA_BUNDLE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt \
        2>/dev/null || print_warning "Could not set Authorino TLS env vars"

    # Step 4: Annotate the MaaS gateway for automatic TLS configuration
    print_step "Annotating maas-default-gateway for Authorino TLS bootstrap..."
    oc annotate gateway maas-default-gateway \
        -n openshift-ingress \
        security.opendatahub.io/authorino-tls-bootstrap="true" \
        --overwrite 2>/dev/null || print_warning "Could not annotate maas-default-gateway (it may not exist yet)"

    # Verification
    print_step "Verifying MaaS TLS configuration..."
    local tls_ok=true

    local cert_annotation=$(oc get service authorino-authorino-authorization -n kuadrant-system \
        -o jsonpath='{.metadata.annotations.service\.beta\.openshift\.io/serving-cert-secret-name}' 2>/dev/null)
    if [ "$cert_annotation" = "authorino-server-cert" ]; then
        print_success "Authorino service has serving-cert annotation"
    else
        print_warning "Authorino service missing serving-cert annotation"
        tls_ok=false
    fi

    local tls_enabled=$(oc get authorino authorino -n kuadrant-system \
        -o jsonpath='{.spec.listener.tls.enabled}' 2>/dev/null)
    if [ "$tls_enabled" = "true" ]; then
        print_success "Authorino TLS listener enabled"
    else
        print_warning "Authorino TLS listener not enabled"
        tls_ok=false
    fi

    if [ "$tls_ok" = true ]; then
        print_success "MaaS TLS configuration complete"
    else
        print_warning "MaaS TLS configuration may be incomplete - check manually"
    fi
}

################################################################################
# MaaS Rate Limiting Fixes
# Fixes WasmPlugin span buffer overflow that prevents token rate limiting
# from working under load. See docs/maas-token-ratelimit-span-buffer-bug.md
################################################################################

configure_maas_rate_limiting() {
    print_step "Configuring MaaS token rate limiting (Redis + EnvoyFilters)..."

    # Fix 1: Deploy Redis for Limitador persistent storage
    if oc get deployment limitador-redis -n kuadrant-system &>/dev/null; then
        print_info "Limitador Redis already deployed"
    else
        print_step "Deploying Redis for Limitador..."
        oc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: limitador-redis
  namespace: kuadrant-system
  labels:
    app: limitador-redis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: limitador-redis
  template:
    metadata:
      labels:
        app: limitador-redis
    spec:
      containers:
      - name: redis
        image: registry.redhat.io/rhel9/redis-7:latest
        ports:
        - containerPort: 6379
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: limitador-redis
  namespace: kuadrant-system
spec:
  selector:
    app: limitador-redis
  ports:
  - port: 6379
    targetPort: 6379
EOF
        oc rollout status deployment/limitador-redis -n kuadrant-system --timeout=60s 2>/dev/null
        print_success "Redis deployed"
    fi

    # Create Redis connection secret
    if ! oc get secret limitador-redis-config -n kuadrant-system &>/dev/null; then
        oc create secret generic limitador-redis-config \
            --from-literal=URL="redis://limitador-redis.kuadrant-system.svc.cluster.local:6379" \
            -n kuadrant-system
    fi

    # Patch Limitador to use redis-cached storage
    local current_storage
    current_storage=$(oc get limitador limitador -n kuadrant-system \
        -o jsonpath='{.spec.storage.redis-cached}' 2>/dev/null || true)
    if [ -z "$current_storage" ]; then
        print_step "Configuring Limitador with redis-cached storage..."
        oc patch limitador limitador -n kuadrant-system --type=merge -p '{
            "spec": {
                "storage": {
                    "redis-cached": {
                        "configSecretRef": {
                            "name": "limitador-redis-config"
                        },
                        "options": {
                            "flush-period": 500,
                            "max-cached": 10000,
                            "batch-size": 100,
                            "response-timeout": 500
                        }
                    }
                }
            }
        }'
        print_success "Limitador configured with Redis-cached storage"
    else
        print_info "Limitador already using redis-cached storage"
    fi

    # Fix 2: Health check interceptor — prevents health probes from saturating
    # the WasmPlugin's 100-span buffer (causing token reports to be dropped)
    if ! oc get envoyfilter healthcheck-filter -n openshift-ingress &>/dev/null; then
        print_step "Applying health check interceptor EnvoyFilter..."
        oc apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: healthcheck-filter
  namespace: openshift-ingress
spec:
  workloadSelector:
    labels:
      gateway.networking.k8s.io/gateway-name: maas-default-gateway
  configPatches:
    - applyTo: HTTP_FILTER
      match:
        context: GATEWAY
        listener:
          filterChain:
            filter:
              name: envoy.filters.network.http_connection_manager
      patch:
        operation: INSERT_FIRST
        value:
          name: envoy.filters.http.health_check
          typed_config:
            "@type": type.googleapis.com/envoy.extensions.filters.http.health_check.v3.HealthCheck
            pass_through_mode: false
            headers:
              - name: ":path"
                string_match:
                  exact: "/healthz"
              - name: ":path"
                string_match:
                  exact: "/ready"
EOF
        print_success "Health check interceptor applied"
    else
        print_info "Health check interceptor already exists"
    fi

    # Fix 3: Increase ratelimit cluster timeout (default ~100ms is too low)
    if ! oc get envoyfilter increase-ratelimit-cluster-timeout -n openshift-ingress &>/dev/null; then
        print_step "Applying ratelimit cluster timeout EnvoyFilter..."
        oc apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: increase-ratelimit-cluster-timeout
  namespace: openshift-ingress
spec:
  workloadSelector:
    labels:
      gateway.networking.k8s.io/gateway-name: maas-default-gateway
  configPatches:
    - applyTo: CLUSTER
      match:
        context: GATEWAY
        cluster:
          name: kuadrant-ratelimit-service
      patch:
        operation: MERGE
        value:
          connect_timeout: 2s
EOF
        print_success "Ratelimit cluster timeout increased to 2s"
    else
        print_info "Ratelimit cluster timeout already configured"
    fi

    # Restart gateway to pick up new filters and clear span buffer
    print_step "Restarting MaaS gateway to apply filters..."
    oc rollout restart deployment/maas-default-gateway-openshift-gateway-controller \
        -n openshift-ingress 2>/dev/null || true
    sleep 10

    print_success "MaaS rate limiting configured (Redis + health check filter + timeout fix)"
}

enable_user_workload_monitoring() {
    print_step "Enabling User Workload Monitoring..."

    oc apply -f "$ROOT_DIR/lib/manifests/monitoring/cluster-monitoring-config.yaml"

    print_success "User Workload Monitoring enabled"
}

install_coo_operator() {
    print_step "Installing Cluster Observability Operator (COO)..."

    if oc get csv -n openshift-cluster-observability-operator 2>/dev/null | grep -q "cluster-observability-operator.*Succeeded"; then
        print_info "COO already installed"
        return 0
    fi

    oc apply -f "$ROOT_DIR/lib/manifests/observability/coo-namespace.yaml"
    oc apply -f "$ROOT_DIR/lib/manifests/observability/coo-operatorgroup.yaml"
    oc apply -f "$ROOT_DIR/lib/manifests/observability/coo-subscription.yaml"

    print_step "Waiting for COO operator to be ready..."
    local elapsed=0
    while [ $elapsed -lt 180 ]; do
        if oc get csv -n openshift-cluster-observability-operator 2>/dev/null | grep -q "cluster-observability-operator.*Succeeded"; then
            print_success "COO operator installed (Perses CRDs available)"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done

    print_warning "COO operator not ready after 180s (may still be installing)"
}

setup_observability_uiplugins() {
    print_step "Setting up observability UIPlugins..."

    if ! oc get crd uiplugins.observability.openshift.io &>/dev/null 2>&1; then
        print_warning "UIPlugin CRD not found — COO may not be installed yet"
        return 0
    fi

    if oc get uiplugin dashboards &>/dev/null 2>&1; then
        local dash_avail
        dash_avail=$(oc get uiplugin dashboards -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
        if [ "$dash_avail" = "True" ]; then
            print_info "UIPlugin 'dashboards' already available [SKIP]"
        fi
    else
        oc apply -f - <<'EOF'
apiVersion: observability.openshift.io/v1alpha1
kind: UIPlugin
metadata:
  name: dashboards
spec:
  type: Dashboards
EOF
    fi

    oc apply -f - <<'EOF'
apiVersion: observability.openshift.io/v1alpha1
kind: UIPlugin
metadata:
  name: monitoring
spec:
  type: Monitoring
  monitoring:
    perses:
      enabled: true
EOF

    local elapsed=0
    while [ $elapsed -lt 60 ]; do
        local mon_avail
        mon_avail=$(oc get uiplugin monitoring -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
        if [ "$mon_avail" = "True" ]; then
            print_success "UIPlugins ready (dashboards + monitoring with Perses)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    print_warning "UIPlugin 'monitoring' not yet Available — check: oc get uiplugin monitoring -o yaml"
}

setup_observability_perses() {
    local mon_ns="redhat-ods-monitoring"

    if ! oc get crd perses.perses.dev &>/dev/null 2>&1; then
        print_warning "Perses CRD not found — skipping Perses server setup"
        return 0
    fi

    if oc get pods -n "$mon_ns" -l app.kubernetes.io/managed-by=perses-operator --no-headers 2>/dev/null | grep -q Running; then
        print_info "Perses already running in $mon_ns [SKIP]"
    else
        print_step "Creating Perses server in $mon_ns..."

        oc create sa perses-sa -n "$mon_ns" 2>/dev/null || true
        oc create clusterrolebinding perses-sa-${mon_ns} \
            --clusterrole=system:openshift:scc:nonroot-v2 \
            --serviceaccount=${mon_ns}:perses-sa 2>/dev/null || true

        oc apply -f - <<EOF
apiVersion: perses.dev/v1alpha2
kind: Perses
metadata:
  name: data-science-perses
  namespace: ${mon_ns}
spec:
  serviceAccountName: perses-sa
  config:
    database:
      file:
        case_sensitive: false
        extension: yaml
        folder: /perses
    datasource:
      disable_local: false
      global:
        disable: false
      project:
        disable: false
    ephemeral_dashboard:
      enable: true
      cleanup_interval: 300s
  client:
    kubernetesAuth:
      enable: false
EOF

        print_step "Waiting for Perses pod..."
        local elapsed=0
        while [ $elapsed -lt 90 ]; do
            if oc get pods -n "$mon_ns" -l app.kubernetes.io/managed-by=perses-operator --no-headers 2>/dev/null | grep -q Running; then
                print_success "Perses server running in $mon_ns"
                break
            fi
            sleep 10
            elapsed=$((elapsed + 10))
        done
    fi

    oc apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: perses-operator-access
  namespace: ${mon_ns}
  labels:
    app.kubernetes.io/managed-by: rhoai-toolkit
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/managed-by: perses-operator
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: openshift-operators
      ports:
        - port: 8080
          protocol: TCP
  policyTypes:
    - Ingress
EOF

    if ! oc get configmap prometheus-web-tls-ca -n "$mon_ns" &>/dev/null; then
        oc apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-web-tls-ca
  namespace: ${mon_ns}
  annotations:
    service.beta.openshift.io/inject-cabundle: "true"
data: {}
EOF
        print_info "Created service-ca ConfigMap for PersesDatasource"
    fi

    oc apply -f "$ROOT_DIR/lib/manifests/monitoring/persesdatasource-monitoring.yaml"

    print_success "Observability Perses setup complete"
}

create_thanos_proxy_secret() {
    local dash_ns="redhat-ods-applications"

    if ! oc get namespace "$dash_ns" &>/dev/null; then
        return 0
    fi

    local obs_enabled
    obs_enabled=$(oc get odhdashboardconfig odh-dashboard-config -n "$dash_ns" \
        -o jsonpath='{.spec.dashboardConfig.observabilityDashboard}' 2>/dev/null || echo "")
    if [ "$obs_enabled" != "true" ]; then
        return 0
    fi

    print_step "Creating Thanos proxy secret for observability dashboard..."

    if oc get secret monitoring-thanos-proxy-secret -n "$dash_ns" &>/dev/null; then
        local existing_token thanos_host http_code
        existing_token=$(oc get secret monitoring-thanos-proxy-secret -n "$dash_ns" \
            -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
        thanos_host=$(oc get route thanos-querier -n openshift-monitoring \
            -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
        if [ -n "$existing_token" ] && [ -n "$thanos_host" ]; then
            http_code=$(curl -sk --connect-timeout 5 --max-time 10 -o /dev/null -w "%{http_code}" \
                -H "Authorization: Bearer ${existing_token}" \
                "https://${thanos_host}/api/v1/query?query=up" 2>/dev/null || echo "000")
            if [ "$http_code" -eq 200 ] 2>/dev/null; then
                print_success "Thanos proxy secret valid (HTTP 200)"
                return 0
            fi
        fi
        oc delete secret monitoring-thanos-proxy-secret -n "$dash_ns" &>/dev/null || true
    fi

    local new_token thanos_host
    new_token=$(oc create token rhods-dashboard -n "$dash_ns" --duration=87600h 2>/dev/null || echo "")
    thanos_host=$(oc get route thanos-querier -n openshift-monitoring \
        -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

    if [ -z "$new_token" ] || [ -z "$thanos_host" ]; then
        print_warning "Could not generate token or find Thanos route"
        return 0
    fi

    oc apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: monitoring-thanos-proxy-secret
  namespace: ${dash_ns}
  labels:
    app.kubernetes.io/part-of: rhods-dashboard
    opendatahub.io/dashboard: "true"
type: Opaque
stringData:
  token: "${new_token}"
  url: "https://${thanos_host}"
EOF

    print_success "Thanos proxy secret created (10-year token)"
}

configure_gateway_telemetry() {
    print_step "Configuring gateway telemetry for MaaS usage metrics..."

    oc apply -f "$ROOT_DIR/lib/manifests/observability/gateway-telemetry-policy.yaml" 2>/dev/null || \
        print_warning "TelemetryPolicy CRD not available (RHCL may need upgrade)"
    oc apply -f "$ROOT_DIR/lib/manifests/observability/istio-gateway-telemetry.yaml" 2>/dev/null || \
        print_warning "Istio Telemetry CRD not available"

    print_success "Gateway telemetry configured"
}

install_rhoai_operator() {
    print_step "Installing Red Hat OpenShift AI Operator..."

    oc create namespace redhat-ods-operator 2>/dev/null || true

    if oc get csv -n redhat-ods-operator 2>/dev/null | grep -q rhods; then
        print_info "RHOAI Operator already installed"
        return 0
    fi

    if [ -z "$RHOAI_CHANNEL" ]; then
        select_rhoai_channel
    else
        print_info "Using specified channel: $RHOAI_CHANNEL"
    fi

    oc apply -f "$ROOT_DIR/lib/manifests/rhoai/rhoai-operatorgroup.yaml"

    print_step "Creating RHOAI subscription with channel: $RHOAI_CHANNEL"
    export RHOAI_CHANNEL
    # NOTE: rhoai-subscription.yaml also references ${INSTALL_PLAN_APPROVAL}. Export
    # and substitute it explicitly (was previously left as a literal, unsubstituted
    # string in the applied Subscription — confirmed live; it happened to work only
    # because OLM falls back to Automatic-like behavior for unrecognized values).
    export INSTALL_PLAN_APPROVAL="Automatic"
    envsubst '${RHOAI_CHANNEL} ${INSTALL_PLAN_APPROVAL}' < "$ROOT_DIR/lib/manifests/rhoai/rhoai-subscription.yaml" | oc apply -f -

    wait_for_operator "rhods" "redhat-ods-operator"

    print_success "RHOAI Operator installed (channel: $RHOAI_CHANNEL)"
}

create_datasciencecluster() {
    print_step "Creating DataScienceCluster..."

    # Apply DSCInitialization first (controls monitoring, trustedCABundle, applications namespace)
    if ! oc get dscinitialization default-dsci &>/dev/null; then
        print_step "Applying DSCInitialization..."
        oc apply -f "$ROOT_DIR/lib/manifests/rhoai/dscinitialization.yaml"
        oc wait --for=jsonpath='{.status.phase}'=Ready dscinitialization/default-dsci --timeout=120s 2>/dev/null || true
    fi

    if oc get datasciencecluster default-dsc &>/dev/null; then
        print_info "DataScienceCluster already exists"
        return 0
    fi

    oc apply -f "$ROOT_DIR/lib/manifests/rhoai/datasciencecluster-v3-35.yaml"

    print_step "Waiting for DataScienceCluster core components..."
    local elapsed=0
    local timeout=300

    while [ $elapsed -lt $timeout ]; do
        local phase=$(oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$phase" = "Ready" ]; then
            print_success "DataScienceCluster is fully ready"
            return 0
        fi
        
        # Check if core components are ready (MaaS/Kueue may need later config steps)
        local dashboard_ready=$(oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions[?(@.type=="DashboardReady")].status}' 2>/dev/null)
        local kserve_ready=$(oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions[?(@.type=="KserveReady")].status}' 2>/dev/null)
        
        if [ "$dashboard_ready" = "True" ] && [ "$kserve_ready" = "True" ]; then
            echo ""
            print_success "Core components ready (Dashboard, KServe)"
            local not_ready=$(oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null)
            if [ -n "$not_ready" ]; then
                print_info "Pending (will be configured in later steps): $not_ready"
            fi
            return 0
        fi
        
        sleep 10
        elapsed=$((elapsed + 10))
        echo -n "."
    done

    echo ""
    print_warning "DataScienceCluster may not be fully ready yet (MaaS/Kueue configured in later steps)"
}

enable_dashboard_features() {
    print_step "Enabling dashboard features..."

    local elapsed=0
    while [ $elapsed -lt 120 ]; do
        if oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications &>/dev/null; then
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    # Build dashboard config with 3.4+ MaaS flags (maasAuthPolicies removed for 3.5 — see below)
    # Required flags per https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/govern_llm_access_with_models-as-a-service:
    #   modelAsService: true          - core MaaS functionality
    #   genAiStudio: true             - MaaS user-facing features in dashboard, incl. MaaS governance page
    #   vLLMDeploymentOnMaaS: true    - Required for "Publish as MaaS" to appear in deploy wizard
    #                                   (without it, dashboard hides the non-legacy deployment path)
    # Developer Preview flags:
    #   mcpCatalog: true              - MCP Catalog under AI Hub (requires MCP Lifecycle Operator)
    # Optional TP flags:
    #   observabilityDashboard: true  - MaaS usage monitoring dashboard (TP)
    # New in 3.5 (applied additively below via --enable-external-models / --enable-tool-calling):
    #   externalModels: true          - View external model endpoints in AI hub (TP)
    #   toolCalling: true             - Validated tool-calling config on Model Catalog cards
    #
    # CONFIRMED BREAKING CHANGE (verified against a live RHOAI 3.5.0 GA cluster):
    #   `maasAuthPolicies` is REJECTED by 3.5's OdhDashboardConfig CEL validation:
    #     "DEPRECATED: spec.dashboardConfig.maasAuthPolicies must be removed or left
    #      unchanged." Setting it on a fresh install (where it doesn't already exist)
    #   fails the patch outright. It is intentionally omitted below for 3.5. The
    #   Subscriptions + Authorization Policies pages it used to gate are now unified
    #   into the "MaaS governance" page under `maasAuthPolicies`'s GA replacement —
    #   governed by `modelAsService`/`genAiStudio` alone as of this writing.
    local patch_json='{
        "spec": {
            "dashboardConfig": {
                "disableModelRegistry": false,
                "disableModelCatalog": false,
                "disableKServeMetrics": false,
                "genAiStudio": true,
                "modelAsService": true,
                "vLLMDeploymentOnMaaS": true,
                "disableLMEval": false,
                "mcpCatalog": true
            }
        }
    }'

    if [ "$ENABLE_VLLM_MAAS" = true ]; then
        patch_json='{
            "spec": {
                "dashboardConfig": {
                    "disableModelRegistry": false,
                    "disableModelCatalog": false,
                    "disableKServeMetrics": false,
                    "genAiStudio": true,
                    "modelAsService": true,
                    "disableLMEval": false,
                    "vLLMDeploymentOnMaaS": true,
                    "mcpCatalog": true
                }
            }
        }'
        print_info "Enabling vLLM runtime for MaaS (Technology Preview)"
    fi

    if [ "$ENABLE_OBSERVABILITY" = true ]; then
        patch_json='{
            "spec": {
                "dashboardConfig": {
                    "disableModelRegistry": false,
                    "disableModelCatalog": false,
                    "disableKServeMetrics": false,
                    "genAiStudio": true,
                    "modelAsService": true,
                    "observabilityDashboard": true,
                    "disableLMEval": false,
                    "mcpCatalog": true
                }
            }
        }'
        print_info "Enabling MaaS observability dashboard (Technology Preview)"
    fi

    oc patch odhdashboardconfig odh-dashboard-config \
        -n redhat-ods-applications \
        --type=merge \
        -p "$patch_json" 2>/dev/null || print_warning "Could not patch dashboard config yet"

    # New 3.5 flags are applied as separate additive merge patches so they combine
    # cleanly with whichever patch_json variant was selected above.
    if [ "$ENABLE_EXTERNAL_MODELS" = true ]; then
        oc patch odhdashboardconfig odh-dashboard-config \
            -n redhat-ods-applications \
            --type=merge \
            -p '{"spec":{"dashboardConfig":{"externalModels": true}}}' 2>/dev/null || true
        print_info "Enabling external model endpoints view (Technology Preview)"
    fi

    if [ "$ENABLE_TOOL_CALLING" = true ]; then
        oc patch odhdashboardconfig odh-dashboard-config \
            -n redhat-ods-applications \
            --type=merge \
            -p '{"spec":{"dashboardConfig":{"toolCalling": true}}}' 2>/dev/null || true
        print_info "Enabling validated tool-calling configuration display on Model Catalog"
    fi

    print_success "Dashboard features enabled (genAiStudio, modelAsService, mcpCatalog)"
}

install_mcp_lifecycle_operator() {
    print_step "Installing MCP Lifecycle Operator (Developer Preview)..."

    if oc get crd mcpservers.mcp.x-k8s.io &>/dev/null; then
        print_success "MCP Lifecycle Operator already installed [SKIP]"
        return 0
    fi

    local MCP_OPERATOR_URL="https://github.com/kubernetes-sigs/mcp-lifecycle-operator/releases/latest/download/install.yaml"

    print_step "Deploying MCP Lifecycle Operator from kubernetes-sigs..."
    # Use 'oc' (not kubectl) — oc is a superset of kubectl for standard manifest
    # operations and is guaranteed to be present wherever this toolkit runs,
    # whereas kubectl may not be installed alongside oc.
    if oc apply -f "$MCP_OPERATOR_URL" &>/dev/null; then
        print_success "MCP Lifecycle Operator deployed"
    else
        print_warning "Could not install MCP Lifecycle Operator — MCP Catalog will not appear in AI Hub"
        return 1
    fi

    local elapsed=0
    while [ $elapsed -lt 120 ]; do
        if oc get pods -n mcp-lifecycle-operator-system 2>/dev/null | grep -q "1/1.*Running"; then
            print_success "MCP Lifecycle Operator is running"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    print_warning "MCP Lifecycle Operator not ready yet — check: oc get pods -n mcp-lifecycle-operator-system"
}

# MCP Catalog prerequisites — the catalog creates MCPServer CRs but does NOT
# auto-create the ServiceAccount, RBAC, or config ConfigMap the server pod needs.
# Call this before deploying from the catalog in any namespace.
setup_mcp_catalog_prerequisites() {
    local namespace="${1:?Namespace required}"

    print_step "Setting up MCP Catalog prerequisites in $namespace..."

    if ! oc get sa mcp-viewer -n "$namespace" &>/dev/null; then
        print_step "Creating mcp-viewer ServiceAccount..."
        oc create serviceaccount mcp-viewer -n "$namespace"
        oc create clusterrolebinding "mcp-viewer-${namespace}" \
            --clusterrole=view \
            --serviceaccount="${namespace}:mcp-viewer" 2>/dev/null || true
        print_success "mcp-viewer ServiceAccount + view ClusterRoleBinding created"
    else
        print_success "mcp-viewer ServiceAccount already exists [SKIP]"
    fi

    if ! oc get configmap openshift-mcp-server-config -n "$namespace" &>/dev/null; then
        print_step "Creating openshift-mcp-server-config ConfigMap..."
        cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: openshift-mcp-server-config
  namespace: $namespace
data:
  config.toml: |
    port = "8080"
    read_only = true
    stateless = true
    toolsets = ["core", "config", "openshift"]
EOF
        print_success "openshift-mcp-server-config ConfigMap created"
    else
        print_success "openshift-mcp-server-config ConfigMap already exists [SKIP]"
    fi
}

create_inference_gateway() {
    print_step "Creating inference Gateways for llm-d/MaaS..."

    get_cluster_domain

    # GatewayClass for OpenShift Gateway Controller
    if ! oc get gatewayclass openshift-gateway-controller &>/dev/null; then
        print_step "Creating openshift-gateway-controller GatewayClass..."
        oc apply -f "$ROOT_DIR/lib/manifests/rhcl/gatewayclass-gateway-controller.yaml"
    fi

    # Gateway resource overrides (2Gi memory to prevent OOMKill from WASM plugins)
    print_step "Applying gateway resource overrides (2Gi memory limit)..."
    oc apply -f "$ROOT_DIR/lib/manifests/rhcl/gateway-resources.yaml"

    # MaaS Gateway - MUST have both annotations for MaaS controller to work in 3.4+ (unchanged in 3.5):
    #   opendatahub.io/managed: "false" - lets MaaS controller manage auth policies
    #   security.opendatahub.io/authorino-tls-bootstrap: "true" - enables TLS to Authorino
    print_step "Creating maas-default-gateway with MaaS annotations..."
    export CERT_NAME="default-gateway-tls"
    envsubst '${CLUSTER_DOMAIN} ${CERT_NAME}' < "$ROOT_DIR/lib/manifests/rhcl/gateway-maas.yaml" | oc apply -f -

    # llm-d inference gateway (for direct model access outside MaaS)
    print_step "Creating openshift-ai-inference gateway..."
    if ! oc get gatewayclass openshift-ai-inference &>/dev/null; then
        oc apply -f "$ROOT_DIR/lib/manifests/rhcl/gatewayclass-ai-inference.yaml"
    fi

    envsubst '${CLUSTER_DOMAIN} ${CERT_NAME}' < "$ROOT_DIR/lib/manifests/rhcl/gateway-inference.yaml" | oc apply -f -

    # Create default-gateway-tls secret for the HTTPS listeners
    # Without this, Envoy never creates the port 443 listener and the gateway returns 503
    create_gateway_tls_secret

    # Create passthrough Route so *.apps.<cluster> wildcard DNS reaches the gateway
    # The gateway gets its own LoadBalancer ELB, but *.apps.<cluster> DNS points to the
    # default OpenShift Router. A passthrough Route bridges the two.
    create_gateway_passthrough_routes

    print_success "Gateways created"
    print_info "MaaS endpoint: https://maas.apps.${CLUSTER_DOMAIN}"
    print_info "Inference endpoint: https://inference-gateway.apps.${CLUSTER_DOMAIN}"
}

create_gateway_tls_secret() {
    if oc get secret default-gateway-tls -n openshift-ingress &>/dev/null; then
        print_success "default-gateway-tls secret already exists"
        return 0
    fi

    print_step "Creating default-gateway-tls secret for gateway HTTPS listeners..."

    # Strategy 0: If no ClusterIssuer exists, try to set up TLS automatically
    local issuer
    issuer=$(oc get clusterissuers -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [ -z "$issuer" ] && [ -f "$ROOT_DIR/scripts/setup-letsencrypt-tls.sh" ]; then
        print_info "No ClusterIssuer found. Running Let's Encrypt TLS setup..."
        "$ROOT_DIR/scripts/setup-letsencrypt-tls.sh" letsencrypt 2>/dev/null || \
            "$ROOT_DIR/scripts/setup-letsencrypt-tls.sh" selfsigned 2>/dev/null || true
        issuer=$(oc get clusterissuers -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    fi

    # Strategy 1: Use cert-manager Certificate CR if a ClusterIssuer exists
    if [ -n "$issuer" ]; then
        print_info "Found ClusterIssuer '$issuer' — creating Certificate CR..."
        export ISSUER_NAME="$issuer"
        envsubst '${CLUSTER_DOMAIN} ${ISSUER_NAME}' < "$ROOT_DIR/lib/manifests/rhcl/gateway-tls-certificate.yaml" | oc apply -f -
        print_step "Waiting for cert-manager to generate TLS secret..."
        local wait=0
        while [ $wait -lt 120 ]; do
            if oc get secret default-gateway-tls -n openshift-ingress &>/dev/null; then
                print_success "default-gateway-tls created by cert-manager"
                return 0
            fi
            sleep 5
            wait=$((wait + 5))
        done
        print_warning "cert-manager did not create secret within 120s"
    fi

    # Strategy 2: Copy from existing wildcard cert (e.g. Let's Encrypt or router default)
    local wildcard_secrets=("apps-wildcard-tls" "cert-manager-ingress-cert" "router-certs-default")
    for src in "${wildcard_secrets[@]}"; do
        if oc get secret "$src" -n openshift-ingress &>/dev/null 2>&1; then
            local cert_cn
            cert_cn=$(oc get secret "$src" -n openshift-ingress -o jsonpath='{.data.tls\.crt}' 2>/dev/null \
                | base64 -d 2>/dev/null | openssl x509 -noout -subject 2>/dev/null || true)
            if echo "$cert_cn" | grep -q "${CLUSTER_DOMAIN}"; then
                print_info "Copying wildcard cert from '$src'..."
                local tmpdir_cert
                tmpdir_cert=$(mktemp -d)
                oc get secret "$src" -n openshift-ingress -o jsonpath='{.data.tls\.crt}' | base64 -d > "$tmpdir_cert/tls.crt"
                oc get secret "$src" -n openshift-ingress -o jsonpath='{.data.tls\.key}' | base64 -d > "$tmpdir_cert/tls.key"
                oc create secret tls default-gateway-tls \
                    --cert="$tmpdir_cert/tls.crt" --key="$tmpdir_cert/tls.key" \
                    -n openshift-ingress --dry-run=client -o yaml | \
                    oc label --local -f - app.kubernetes.io/managed-by=rhoai-toolkit --dry-run=client -o yaml | \
                    oc apply -f -
                rm -rf "$tmpdir_cert"
                print_success "default-gateway-tls created from '$src'"
                return 0
            fi
        fi
    done

    # Strategy 3: Check openshift-ingress-operator for router-ca
    if oc get secret router-ca -n openshift-ingress-operator &>/dev/null 2>&1; then
        print_info "Using OpenShift router-ca to generate self-signed gateway cert..."
        local ca_crt ca_key
        ca_crt=$(oc get secret router-ca -n openshift-ingress-operator -o jsonpath='{.data.tls\.crt}' | base64 -d)
        ca_key=$(oc get secret router-ca -n openshift-ingress-operator -o jsonpath='{.data.tls\.key}' | base64 -d)
        local tmpdir
        tmpdir=$(mktemp -d)
        echo "$ca_crt" > "$tmpdir/ca.crt"
        echo "$ca_key" > "$tmpdir/ca.key"
        openssl req -new -newkey rsa:2048 -nodes \
            -keyout "$tmpdir/tls.key" -out "$tmpdir/tls.csr" \
            -subj "/CN=*.apps.${CLUSTER_DOMAIN}" \
            -addext "subjectAltName=DNS:*.apps.${CLUSTER_DOMAIN},DNS:apps.${CLUSTER_DOMAIN}" 2>/dev/null
        openssl x509 -req -in "$tmpdir/tls.csr" -CA "$tmpdir/ca.crt" -CAkey "$tmpdir/ca.key" \
            -CAcreateserial -out "$tmpdir/tls.crt" -days 365 \
            -extfile <(printf "subjectAltName=DNS:*.apps.${CLUSTER_DOMAIN},DNS:apps.${CLUSTER_DOMAIN}") 2>/dev/null
        oc create secret tls default-gateway-tls \
            --cert="$tmpdir/tls.crt" --key="$tmpdir/tls.key" \
            -n openshift-ingress 2>/dev/null
        rm -rf "$tmpdir"
        print_success "default-gateway-tls created (signed by router-ca)"
        return 0
    fi

    print_error "Could not create default-gateway-tls — no cert-manager, wildcard cert, or router-ca found"
    print_info "Create it manually: oc create secret tls default-gateway-tls --cert=tls.crt --key=tls.key -n openshift-ingress"
    return 1
}

create_gateway_passthrough_routes() {
    # The *.apps.<cluster> wildcard DNS points to the default OpenShift Router,
    # but gateway pods get their own LoadBalancer. A passthrough Route bridges them.
    local gateways=("maas-default-gateway:maas" "openshift-ai-inference:inference-gateway")

    for entry in "${gateways[@]}"; do
        local gw_name="${entry%%:*}"
        local hostname_prefix="${entry##*:}"
        local route_name="${gw_name}-passthrough"
        local hostname="${hostname_prefix}.apps.${CLUSTER_DOMAIN}"

        if oc get route "$route_name" -n openshift-ingress &>/dev/null; then
            print_info "Passthrough route '$route_name' already exists"
            continue
        fi

        local svc_name
        svc_name=$(oc get svc -n openshift-ingress -l "gateway.networking.k8s.io/gateway-name=${gw_name}" \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

        if [ -z "$svc_name" ]; then
            print_warning "No service found for gateway '$gw_name' — skipping passthrough route"
            continue
        fi

        print_step "Creating passthrough route: ${hostname} → ${svc_name}..."
        export ROUTE_NAME="$route_name"
        export HOSTNAME="$hostname"
        export SERVICE_NAME="$svc_name"
        envsubst '${ROUTE_NAME} ${HOSTNAME} ${SERVICE_NAME}' \
            < "$ROOT_DIR/lib/manifests/rhcl/gateway-passthrough-route.yaml" | oc apply -f -
    done
    print_success "Gateway passthrough routes configured"
}

create_hardware_profile() {
    print_step "Creating default GPU hardware profile..."

    oc apply -f "$ROOT_DIR/lib/manifests/rhoai/hardware-profile-gpu.yaml"

    print_success "Hardware profile created"
}

################################################################################
# Monitoring Dashboards
################################################################################

deploy_observe_dashboards() {
    print_step "Deploying dashboards to OpenShift Observe tab..."

    local dashboard_dir="$ROOT_DIR/lib/manifests/dashboards"
    local namespace="openshift-config-managed"

    local cm_names="nvidia-dcgm-exporter-dashboard vllm-performance-dashboard vllm-advanced-dashboard"
    local cm_files="dcgm-exporter-dashboard.json vllm-performance-ocp.json vllm-advanced-ocp.json"

    local i=1
    for cm_name in $cm_names; do
        local file
        file=$(echo "$cm_files" | cut -d' ' -f"$i")
        i=$((i + 1))
        if [ ! -f "$dashboard_dir/$file" ]; then
            print_warning "Dashboard file not found: $dashboard_dir/$file"
            continue
        fi

        if oc get configmap "$cm_name" -n "$namespace" &>/dev/null; then
            print_info "Dashboard '$cm_name' already exists [SKIP]"
            continue
        fi

        oc create configmap "$cm_name" \
            -n "$namespace" \
            --from-file="$dashboard_dir/$file"

        oc label configmap "$cm_name" \
            -n "$namespace" \
            "console.openshift.io/dashboard=true" --overwrite

        oc label configmap "$cm_name" \
            -n "$namespace" \
            "console.openshift.io/odc-dashboard=true" --overwrite
    done

    print_success "Dashboards deployed -> Observe > Dashboards"
}

deploy_grafana_monitoring() {
    print_step "Deploying Grafana monitoring stack..."

    local grafana_ns="monitoring"
    oc create namespace "$grafana_ns" 2>/dev/null || true

    if oc get deployment grafana -n "$grafana_ns" &>/dev/null; then
        print_info "Grafana already deployed [SKIP]"
    else
        oc apply -f "$ROOT_DIR/lib/manifests/grafana/grafana-deployment.yaml" -n "$grafana_ns"
        print_step "Waiting for Grafana pod..."
        oc wait --for=condition=ready pod -l app=grafana -n "$grafana_ns" --timeout=120s 2>/dev/null || true
        print_success "Grafana deployed"
    fi

    oc apply -f "$ROOT_DIR/lib/manifests/grafana/prometheus-token.yaml" 2>/dev/null || true

    local token=""
    local retries=0
    while [ $retries -lt 6 ] && [ -z "$token" ]; do
        token=$(oc get secret grafana-prometheus-token -n openshift-monitoring \
            -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null)
        [ -z "$token" ] && sleep 5 && retries=$((retries + 1))
    done

    if [ -z "$token" ]; then
        token=$(oc create token prometheus-k8s -n openshift-monitoring --duration=87600h 2>/dev/null || true)
    fi

    if [ -z "$token" ]; then
        print_warning "Could not get Prometheus token for Grafana datasource"
        return 0
    fi

    local grafana_route
    grafana_route=$(oc get route grafana -n "$grafana_ns" -o jsonpath='{.spec.host}' 2>/dev/null)

    if [ -n "$grafana_route" ]; then
        print_step "Configuring Prometheus datasource..."
        curl -sk -X POST "https://${grafana_route}/api/datasources" \
            -u admin:admin \
            -H "Content-Type: application/json" \
            -d "{
                \"name\": \"Prometheus\",
                \"type\": \"prometheus\",
                \"url\": \"https://thanos-querier.openshift-monitoring.svc:9091\",
                \"access\": \"proxy\",
                \"isDefault\": true,
                \"jsonData\": {
                    \"httpHeaderName1\": \"Authorization\",
                    \"tlsSkipVerify\": true
                },
                \"secureJsonData\": {
                    \"httpHeaderValue1\": \"Bearer ${token}\"
                }
            }" &>/dev/null && print_success "Prometheus datasource configured" \
            || print_info "Datasource may already exist"

        for dashboard_file in "$ROOT_DIR"/lib/manifests/grafana/*-dashboard.json; do
            [ -f "$dashboard_file" ] || continue
            local dash_name
            dash_name=$(basename "$dashboard_file" .json)
            print_step "Importing dashboard: $dash_name..."
            local dash_json
            dash_json=$(cat "$dashboard_file")
            curl -sk -X POST "https://${grafana_route}/api/dashboards/db" \
                -u admin:admin \
                -H "Content-Type: application/json" \
                -d "{\"dashboard\": ${dash_json}, \"overwrite\": true}" &>/dev/null \
                && print_success "  Imported: $dash_name" \
                || print_warning "  Failed to import: $dash_name"
        done
    fi

    get_cluster_domain
    export CLUSTER_DOMAIN
    envsubst '${CLUSTER_DOMAIN}' < "$ROOT_DIR/lib/manifests/monitoring/consolelinks-grafana.yaml" | oc apply -f - 2>/dev/null || true
    envsubst '${CLUSTER_DOMAIN}' < "$ROOT_DIR/lib/manifests/monitoring/odhapplication-grafana.yaml" | oc apply -f - 2>/dev/null || true

    print_success "Grafana monitoring stack deployed"
    if [ -n "$grafana_route" ]; then
        print_info "Grafana URL: https://${grafana_route}"
        print_info "Dashboards: GPU Metrics (DCGM), vLLM Inference, vLLM Advanced"
    fi
}

create_mlflow_server() {
    print_step "Creating MLflow server instance..."

    if oc get mlflow mlflow &>/dev/null 2>&1; then
        local mlflow_ready=$(oc get mlflow mlflow -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
        if [ "$mlflow_ready" = "True" ]; then
            print_success "MLflow server already exists and is ready"
            return 0
        fi
        print_info "MLflow server exists but not yet ready"
        return 0
    fi

    if ! oc get crd mlflows.mlflow.opendatahub.io &>/dev/null 2>&1; then
        print_warning "MLflow CRD not found — MLflow operator may not be ready yet"
        print_info "You can create it later: oc apply -f <mlflow-cr.yaml>"
        return 0
    fi

    if oc get deployment postgres -n redhat-ods-applications &>/dev/null; then
        print_info "Using existing PostgreSQL for MLflow backend..."
        local pg_pod
        pg_pod=$(oc get pods -n redhat-ods-applications -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$pg_pod" ]; then
            oc exec "$pg_pod" -n redhat-ods-applications -- bash -c \
                'PGPASSWORD=$POSTGRES_PASSWORD psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname='"'"'mlflow'"'"'" | grep -q 1 || \
                 PGPASSWORD=$POSTGRES_PASSWORD psql -U postgres -c "CREATE DATABASE mlflow OWNER maas;"' 2>/dev/null || true
        fi

        local pg_url
        pg_url=$(oc get secret maas-db-config -n redhat-ods-applications \
            -o jsonpath='{.data.DB_CONNECTION_URL}' 2>/dev/null | base64 -d 2>/dev/null | sed 's|/maas|/mlflow|')

        if [ -n "$pg_url" ]; then
            oc create secret generic mlflow-db-credentials \
                --from-literal=database-url="$pg_url" \
                -n redhat-ods-applications \
                --dry-run=client -o yaml | oc apply -f - 2>/dev/null

            oc apply -f - <<'EOF'
apiVersion: mlflow.opendatahub.io/v1
kind: MLflow
metadata:
  name: mlflow
spec:
  replicas: 1
  backendStoreUriFrom:
    name: mlflow-db-credentials
    key: database-url
  serveArtifacts: true
  artifactsDestination: "file:///mlflow/artifacts"
  storage:
    size: 10Gi
EOF
            print_info "MLflow configured with PostgreSQL backend"
        else
            print_warning "Could not read PostgreSQL URL, falling back to SQLite"
            oc apply -f "$ROOT_DIR/lib/manifests/rhoai/mlflow-cr.yaml"
        fi
    else
        oc apply -f "$ROOT_DIR/lib/manifests/rhoai/mlflow-cr.yaml"
        print_info "MLflow configured with SQLite backend (PVC)"
    fi

    print_step "Waiting for MLflow server to be ready..."
    local wait=0
    while [ $wait -lt 180 ]; do
        local ready=$(oc get mlflow mlflow -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
        if [ "$ready" = "True" ]; then
            local url=$(oc get mlflow mlflow -o jsonpath='{.status.url}' 2>/dev/null)
            print_success "MLflow server is ready: ${url}"
            return 0
        fi
        sleep 10
        wait=$((wait + 10))
    done

    print_warning "MLflow server not ready yet (may still be starting) — check: oc get mlflow mlflow"
}

verify_maas_deployment() {
    print_step "Verifying MaaS deployment..."

    # Check MaaS CRDs
    local maas_crds=$(oc get crd 2>/dev/null | grep -c "maas.opendatahub.io" || echo "0")
    if [ "$maas_crds" -ge 3 ]; then
        print_success "MaaS CRDs installed ($maas_crds found)"
    else
        print_warning "MaaS CRDs not fully installed yet ($maas_crds found, expected 5)"
        print_info "Expected CRDs: maassubscriptions, maasauthpolicies, maasmodelrefs, tenants, externalmodels"
    fi

    # Check Tenant CR
    local tenant_ready=$(oc get tenant default-tenant -n models-as-a-service \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [ "$tenant_ready" = "True" ]; then
        print_success "MaaS Tenant 'default-tenant' is Ready"
    elif [ -n "$tenant_ready" ]; then
        local tenant_msg=$(oc get tenant default-tenant -n models-as-a-service \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null)
        print_warning "MaaS Tenant not ready yet: $tenant_msg"
    else
        print_info "MaaS Tenant not found yet (it will be auto-created by the MaaS controller)"
    fi

    # Check maas-db-config secret
    print_step "Checking maas-db-config secret..."
    if oc get secret maas-db-config -n redhat-ods-applications &>/dev/null; then
        local has_url=$(oc get secret maas-db-config -n redhat-ods-applications \
            -o jsonpath='{.data.DB_CONNECTION_URL}' 2>/dev/null)
        if [ -n "$has_url" ]; then
            print_success "maas-db-config secret exists with DB_CONNECTION_URL"
        else
            print_warning "maas-db-config secret exists but may be missing DB_CONNECTION_URL key"
        fi
    else
        print_warning "maas-db-config secret NOT found — MaaS Tenant will show Degraded"
    fi

    # Check User Workload Monitoring
    local uwm=$(oc get configmap cluster-monitoring-config -n openshift-monitoring \
        -o jsonpath='{.data.config\.yaml}' 2>/dev/null | grep -c "enableUserWorkload: true" || echo "0")
    if [ "$uwm" -gt 0 ]; then
        print_success "User Workload Monitoring is enabled"
    else
        print_warning "User Workload Monitoring may not be enabled - MaaS requires it"
    fi

    # Check Gateway
    local gw_exists=$(oc get gateway maas-default-gateway -n openshift-ingress &>/dev/null && echo "yes" || echo "no")
    if [ "$gw_exists" = "yes" ]; then
        local gw_managed=$(oc get gateway maas-default-gateway -n openshift-ingress \
            -o jsonpath='{.metadata.annotations.opendatahub\.io/managed}' 2>/dev/null)
        local gw_tls=$(oc get gateway maas-default-gateway -n openshift-ingress \
            -o jsonpath='{.metadata.annotations.security\.opendatahub\.io/authorino-tls-bootstrap}' 2>/dev/null)
        if [ "$gw_managed" = "false" ] && [ "$gw_tls" = "true" ]; then
            print_success "maas-default-gateway has correct annotations"
        else
            print_warning "maas-default-gateway missing required annotations"
            [ "$gw_managed" != "false" ] && print_info "  Missing: opendatahub.io/managed: \"false\""
            [ "$gw_tls" != "true" ] && print_info "  Missing: security.opendatahub.io/authorino-tls-bootstrap: \"true\""
        fi
    else
        print_warning "maas-default-gateway not found"
    fi

    # Check Authorino TLS
    local auth_tls=$(oc get authorino authorino -n kuadrant-system \
        -o jsonpath='{.spec.listener.tls.enabled}' 2>/dev/null)
    if [ "$auth_tls" = "true" ]; then
        print_success "Authorino TLS listener is enabled"
    else
        print_warning "Authorino TLS listener not enabled"
    fi

    # Check MaaS API health endpoint
    print_step "Checking MaaS API health endpoint..."
    local maas_health
    maas_health=$(curl -sk "https://maas.apps.${CLUSTER_DOMAIN}/maas-api/health" 2>/dev/null || true)
    if echo "$maas_health" | grep -q "healthy"; then
        print_success "MaaS API health endpoint responding: $maas_health"
    elif [ -n "$maas_health" ]; then
        print_warning "MaaS API health endpoint returned: $maas_health"
    else
        print_info "MaaS API health endpoint not reachable yet (maas-api may still be starting)"
    fi
}

################################################################################
# User Management
################################################################################

setup_demo_users() {
    local num_users="${1:-5}"
    local admin_group="${2:-rhods-admins}"
    local user_group="${3:-rhods-users}"
    local password="${4:-openshift}"

    print_step "Setting up ${num_users} demo users with groups '${admin_group}' and '${user_group}'..."

    # Ensure htpasswd is available
    if ! command -v htpasswd &>/dev/null; then
        if command -v python3 &>/dev/null; then
            _htpasswd_add() {
                local file="$1" user="$2" pass="$3"
                local hash
                hash=$(python3 -c "import bcrypt; print(bcrypt.hashpw('${pass}'.encode(), bcrypt.gensalt()).decode())" 2>/dev/null) || \
                hash=$(python3 -c "import passlib.hash; print(passlib.hash.bcrypt.hash('${pass}'))" 2>/dev/null) || \
                hash=$(openssl passwd -apr1 "${pass}" 2>/dev/null)
                echo "${user}:${hash}" >> "$file"
            }
        else
            print_error "htpasswd or python3 required for user creation"
            return 1
        fi
    fi

    local tmpdir
    tmpdir=$(mktemp -d)
    local htpasswd_file="${tmpdir}/htpasswd"
    touch "$htpasswd_file"

    # Collect existing htpasswd data if it exists
    if oc get secret htpasswd-secret -n openshift-config &>/dev/null 2>&1; then
        oc get secret htpasswd-secret -n openshift-config -o jsonpath='{.data.htpasswd}' 2>/dev/null \
            | base64 -d > "$htpasswd_file" 2>/dev/null || true
    fi

    local admin_users=""
    local regular_users=""

    for i in $(seq 1 "$num_users"); do
        local username="user${i}"
        if grep -q "^${username}:" "$htpasswd_file" 2>/dev/null; then
            print_info "User '${username}' already exists in htpasswd — skipping"
        else
            if command -v htpasswd &>/dev/null; then
                htpasswd -bB "$htpasswd_file" "$username" "$password" 2>/dev/null
            else
                _htpasswd_add "$htpasswd_file" "$username" "$password"
            fi
            print_info "Created user '${username}'"
        fi

        if [ "$i" -eq 1 ]; then
            admin_users="${username}"
        else
            regular_users="${regular_users:+${regular_users},}${username}"
        fi
    done

    # Create/update htpasswd secret
    oc create secret generic htpasswd-secret \
        --from-file=htpasswd="$htpasswd_file" \
        -n openshift-config --dry-run=client -o yaml | oc apply -f -

    # Ensure htpasswd identity provider is configured
    local has_htpasswd
    has_htpasswd=$(oc get oauth cluster -o jsonpath='{.spec.identityProviders[?(@.name=="htpasswd")].name}' 2>/dev/null || true)
    if [ -z "$has_htpasswd" ]; then
        print_step "Adding htpasswd identity provider to OAuth..."
        oc patch oauth cluster --type=json -p '[{
            "op": "add",
            "path": "/spec/identityProviders/-",
            "value": {
                "name": "htpasswd",
                "type": "HTPasswd",
                "mappingMethod": "claim",
                "htpasswd": {
                    "fileData": {
                        "name": "htpasswd-secret"
                    }
                }
            }
        }]' 2>/dev/null || {
            oc patch oauth cluster --type=merge -p '{
                "spec": {
                    "identityProviders": [{
                        "name": "htpasswd",
                        "type": "HTPasswd",
                        "mappingMethod": "claim",
                        "htpasswd": {
                            "fileData": {
                                "name": "htpasswd-secret"
                            }
                        }
                    }]
                }
            }' 2>/dev/null
        }
        print_info "OAuth will restart — users may take 1-2 minutes to become available"
    fi

    # Create groups
    for grp in "$admin_group" "$user_group"; do
        if ! oc get group "$grp" &>/dev/null 2>&1; then
            print_step "Creating group '${grp}'..."
            oc adm groups new "$grp" 2>/dev/null || true
        fi
    done

    # Add user1 to admin group, rest to user group
    if [ -n "$admin_users" ]; then
        print_step "Adding ${admin_users} to '${admin_group}' (admin)..."
        oc adm groups add-users "$admin_group" "$admin_users" 2>/dev/null || true
        # Give cluster-admin to admin users for RHOAI dashboard access
        oc adm policy add-cluster-role-to-user cluster-admin "$admin_users" 2>/dev/null || true
    fi

    if [ -n "$regular_users" ]; then
        local IFS=','
        for u in $regular_users; do
            oc adm groups add-users "$user_group" "$u" 2>/dev/null || true
        done
        unset IFS
        print_step "Added ${num_users-1} users to '${user_group}' (regular)"
    fi

    rm -rf "$tmpdir"

    print_success "Demo users created:"
    echo -e "  ${CYAN}Admin group (${admin_group}):${NC} ${admin_users}"
    echo -e "  ${CYAN}User group (${user_group}):${NC} ${regular_users}"
    echo -e "  ${CYAN}Password:${NC} ${password}"
    echo -e "  ${CYAN}Login:${NC} oc login -u user1 -p ${password}"
    echo ""
    echo -e "  ${YELLOW}Note:${NC} When creating MaaS Subscriptions, set owner group to '${admin_group}' or '${user_group}'"
    echo -e "  ${YELLOW}Note:${NC} Users may take 1-2 minutes to be available after OAuth restart"
}

print_summary() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          RHOAI 3.5 Installation Complete!                      ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Dashboard route naming: some 3.4+ docs/environments use "rh-ai" as the primary
    # route, but on a live RHOAI 3.5.0 GA cluster tested here, only "data-science-gateway"
    # existed (no "rh-ai" route was created). This fallback chain checks both, so it
    # works correctly either way — the comment is kept accurate to what's been observed.
    local dashboard_url=$(oc get route -n redhat-ods-applications -o jsonpath='{.items[?(@.metadata.name=="rh-ai")].spec.host}' 2>/dev/null)
    if [ -z "$dashboard_url" ]; then
        dashboard_url=$(oc get route -n redhat-ods-applications -o jsonpath='{.items[?(@.metadata.name=="data-science-gateway")].spec.host}' 2>/dev/null)
    fi
    if [ -z "$dashboard_url" ]; then
        dashboard_url="rh-ai.apps.${CLUSTER_DOMAIN}"
    fi

    echo -e "${CYAN}Dashboard URL:${NC} https://${dashboard_url}"
    echo -e "${CYAN}Current User:${NC} $(oc whoami 2>/dev/null)"

    local admin_in_htpasswd=false
    if oc get secret htpasswd-secret -n openshift-config &>/dev/null; then
        if oc get secret htpasswd-secret -n openshift-config \
            -o jsonpath='{.data.htpasswd}' 2>/dev/null | base64 -d 2>/dev/null | grep -q "^admin:"; then
            admin_in_htpasswd=true
        fi
    fi

    if [ "$admin_in_htpasswd" = true ]; then
        echo -e "${CYAN}Admin Login:${NC}  admin / R3dh4t1!"
        echo ""
        echo -e "${YELLOW}Post-install:${NC} Log in as 'admin' for MaaS API key generation:"
        echo "  oc login -u admin -p 'R3dh4t1!' $(oc whoami --show-server 2>/dev/null)"
        echo "  To remove kubeadmin, use the toolkit: ./rhoai-toolkit.sh → RHOAI Management → Day 2 Operations"
    else
        echo ""
        echo -e "${YELLOW}Post-install:${NC} No htpasswd admin user was created."
        echo "  To create one later: $0 (re-run and choose Y at the admin user prompt)"
        echo "  Or use: scripts/setup-users.sh to create demo users"
    fi

    if [ "$ENABLE_LLMD" = true ] && [ "$SKIP_RHCL" = false ]; then
        echo -e "${CYAN}MaaS Gateway:${NC} https://maas.apps.${CLUSTER_DOMAIN}"
        echo -e "${CYAN}Inference Gateway:${NC} https://inference-gateway.apps.${CLUSTER_DOMAIN}"
    fi

    echo ""
    echo -e "${GREEN}What's New in 3.5:${NC}"
    echo "  • EvalHub now GA (SDK, CLI, MCP server, per-tenant deployment)"
    echo "  • External OIDC authentication for MaaS now GA (was TP in 3.4)"
    echo "  • Automated Red Teaming (Garak) now GA"
    echo "  • Responses API on OGX (formerly Llama Stack) now GA"
    echo "  • Priority-based flow control for llm-d now GA (breaking API changes — see script header)"
    echo "  • MLflow integration for AI Pipelines, Kubeflow Trainer, and workbenches"
    echo "  • Kueue scheduling visibility in workbenches; self-managed ClusterQueues/LocalQueues"
    echo "  • Canary rollout support for KServe RawDeployment"
    echo "  • MaaS body-based model routing (OpenAI-compatible /v1/chat/completions)"
    echo "  • New Technology Preview: MCP gateway/lifecycle operators, MaaS multi-tenancy,"
    echo "    AutoGluon runtime, Docling SDK/Serve GPU images, external model endpoints view"
    echo ""

    # Show PostgreSQL info
    if oc get secret maas-db-config -n redhat-ods-applications &>/dev/null; then
        if oc get deployment postgres -n redhat-ods-applications &>/dev/null; then
            echo -e "${YELLOW}PostgreSQL:${NC} POC instance in redhat-ods-applications (NOT for production)"
            echo "  For production: AWS RDS, Crunchy Operator, or Azure Database for PostgreSQL"
        else
            echo -e "${CYAN}PostgreSQL:${NC} External (maas-db-config secret exists)"
        fi
        echo ""
    fi

    echo -e "${YELLOW}MaaS Next Steps (subscription model, unchanged in 3.5):${NC}"
    echo "  1. Access dashboard > Settings > verify MaaS is active"
    echo "  2. Deploy a model and publish to MaaS (creates MaaSModelRef)"
    echo "  3. Create a MaaS Subscription (dashboard Settings > MaaS governance)"
    echo "     Note: 3.5 unifies Subscriptions + Authorization Policies into one 'MaaS governance' page"
    echo "  4. Create a MaaS Authorization Policy (dashboard Settings > MaaS governance)"
    echo "  5. Generate API keys for users (dashboard or self-service)"
    echo "  6. Verify: oc get tenant default-tenant -n models-as-a-service"
    echo "  7. Verify: oc get maassubscriptions -n models-as-a-service"
    if [ "$ENABLE_VLLM_MAAS" = true ]; then
        echo "  • vLLM on MaaS is enabled (TP) - deploy models via MaaS with vLLM runtime"
    fi
    if [ "$ENABLE_OBSERVABILITY" = true ]; then
        echo "  • MaaS observability dashboard is enabled (TP)"
    fi
    if [ "$ENABLE_EXTERNAL_MODELS" = true ]; then
        echo "  • External model endpoints view is enabled (TP) - AI hub > Models > External models tab"
    fi
    if [ "$ENABLE_TOOL_CALLING" = true ]; then
        echo "  • Validated tool-calling config display is enabled on Model Catalog cards"
    fi
    echo ""

    echo -e "${BLUE}Verification commands:${NC}"
    echo "  oc get datasciencecluster"
    echo "  oc get csv -n redhat-ods-operator"
    echo "  oc get hardwareprofiles -n redhat-ods-applications"
    echo "  oc get crd | grep maas.opendatahub.io"
    echo "  oc get tenant -n models-as-a-service"
    echo "  oc get gateway maas-default-gateway -n openshift-ingress"
    echo "  oc get authorino authorino -n kuadrant-system -o jsonpath='{.spec.listener.tls}'"
    echo ""
}

################################################################################
# Main
################################################################################

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-prerequisites)
                SKIP_PREREQUISITES=true
                shift
                ;;
            --skip-rhcl)
                SKIP_RHCL=true
                shift
                ;;
            --skip-node-scaling)
                SKIP_NODE_SCALING=true
                shift
                ;;
            --skip-maas)
                SKIP_MAAS=true
                shift
                ;;
            --no-llmd)
                ENABLE_LLMD=false
                shift
                ;;
            --enable-vllm-maas)
                ENABLE_VLLM_MAAS=true
                shift
                ;;
            --enable-observability)
                ENABLE_OBSERVABILITY=true
                shift
                ;;
            --enable-external-models)
                ENABLE_EXTERNAL_MODELS=true
                shift
                ;;
            --enable-tool-calling)
                ENABLE_TOOL_CALLING=true
                shift
                ;;
            --deploy-grafana)
                DEPLOY_GRAFANA=true
                shift
                ;;
            --postgres-connection)
                POSTGRES_CONNECTION="$2"
                shift 2
                ;;
            --skip-maas-db)
                SKIP_MAAS_DB=true
                shift
                ;;
            --skip-admin-user)
                SKIP_ADMIN_USER=true
                shift
                ;;
            --channel)
                RHOAI_CHANNEL="$2"
                shift 2
                ;;
            --domain)
                CLUSTER_DOMAIN="$2"
                shift 2
                ;;
            --timeout)
                WAIT_TIMEOUT="$2"
                shift 2
                ;;
            --setup-pipelines)
                SETUP_PIPELINES=true
                shift
                ;;
            --pipeline-namespace)
                SETUP_PIPELINES=true
                PIPELINE_NAMESPACE="$2"
                shift 2
                ;;
            --setup-users)
                SETUP_USERS=true
                shift
                ;;
            --num-users)
                SETUP_USERS=true
                NUM_USERS="$2"
                shift 2
                ;;
            --admin-group)
                ADMIN_GROUP="$2"
                shift 2
                ;;
            --user-group)
                USER_GROUP="$2"
                shift 2
                ;;
            --user-password)
                USER_PASSWORD="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    print_banner
    check_prerequisites
    get_cluster_domain

    if [ "$SKIP_ADMIN_USER" = true ]; then
        print_info "Skipping admin user creation (--skip-admin-user)"
    elif [ "$CREATE_ADMIN_USER" = "yes" ]; then
        create_admin_user
    else
        echo ""
        echo -e "${CYAN}Would you like to create an htpasswd admin user?${NC}"
        echo -e "  This creates user ${YELLOW}'admin'${NC} with password ${YELLOW}'R3dh4t1!'${NC} and cluster-admin role."
        echo -e "  You can skip this if you already have an identity provider configured."
        echo ""
        read -p "Create admin user? (Y/n): " admin_choice
        admin_choice=${admin_choice:-Y}
        if [[ "$admin_choice" =~ ^[Yy]$ ]]; then
            create_admin_user
        else
            print_info "Skipping admin user creation"
        fi
    fi

    if [ "$SKIP_NODE_SCALING" = false ]; then
        scale_cluster_nodes
    else
        print_info "Skipping node scaling (--skip-node-scaling)"
    fi

    if [ "$SKIP_PREREQUISITES" = false ]; then
        install_nfd_operator
        install_gpu_operator
        install_kueue_operator
        install_certmanager_operator

        if [ "$ENABLE_LLMD" = true ]; then
            install_lws_operator
        fi
    fi

    if [ "$SKIP_RHCL" = false ] && [ "$SKIP_MAAS" = false ]; then
        install_rhcl_operator
        create_inference_gateway
    elif [ "$SKIP_RHCL" = false ]; then
        install_rhcl_operator
    else
        print_info "Skipping RHCL/MaaS (--skip-rhcl or --skip-maas)"
    fi

    enable_user_workload_monitoring

    install_rhoai_operator
    create_datasciencecluster

    enable_dashboard_features
    # Developer Preview / optional feature — its function body already returns
    # non-zero on failure (e.g. unreachable URL, CRD not ready in time). Guard
    # the call so a failure here doesn't abort the rest of the install under `set -e`.
    install_mcp_lifecycle_operator || true
    create_hardware_profile
    create_mlflow_server

    # MaaS DB + TLS setup (3.4+, unchanged in 3.5) - must run after RHCL and gateway are created
    # DB secret must exist BEFORE modelsAsService becomes Managed (or restart maas-api after)
    if [ "$SKIP_RHCL" = false ] && [ "$SKIP_MAAS" = false ]; then
        if [ "$SKIP_MAAS_DB" = false ]; then
            setup_maas_database
        else
            print_info "Skipping MaaS DB setup (--skip-maas-db)"
            if ! oc get secret maas-db-config -n redhat-ods-applications &>/dev/null; then
                print_warning "maas-db-config secret not found — MaaS Tenant will show Degraded"
                print_info "Create it with: oc create secret generic maas-db-config \\"
                print_info "  --from-literal=DB_CONNECTION_URL='postgresql://user:pass@host:5432/db?sslmode=require' \\"
                print_info "  -n redhat-ods-applications"
            fi
        fi
        configure_maas_tls
        configure_maas_rate_limiting
        verify_maas_deployment
    fi

    # Observability stack — COO + UIPlugins + Perses + Thanos proxy are always installed.
    # Without these the RHOAI "Observability dashboard" shows "Service Unavailable".
    install_coo_operator
    setup_observability_uiplugins
    setup_observability_perses
    create_thanos_proxy_secret

    # Native Observe tab dashboards (zero-dependency, always deployed)
    deploy_observe_dashboards

    # Standalone Grafana instance (optional, controlled by --deploy-grafana)
    if [ "${DEPLOY_GRAFANA:-false}" = true ]; then
        deploy_grafana_monitoring
    fi

    # Gateway telemetry (MaaS usage metrics) is optional
    if [ "$ENABLE_OBSERVABILITY" = true ]; then
        configure_gateway_telemetry
    fi

    if [ "$SETUP_PIPELINES" = true ]; then
        setup_pipeline_server "$PIPELINE_NAMESPACE"
    fi

    if [ "$SETUP_USERS" = true ]; then
        setup_demo_users "$NUM_USERS" "$ADMIN_GROUP" "$USER_GROUP" "$USER_PASSWORD"
    fi

    print_summary
}

main "$@"
exit 0
