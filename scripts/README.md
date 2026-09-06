# Utility Scripts

This folder contains utility scripts that support the main installation workflows.

## Scripts

---

### check-aws-prerequisites.sh
**Purpose**: Validate AWS environment before OpenShift installation

**Usage**:
```bash
# Run standalone check
./scripts/check-aws-prerequisites.sh

# Or it runs automatically in rhoai-toolkit.sh
```

**What it checks**:
- ✅ AWS CLI installation and credentials
- ✅ Route53 hosted zones (public vs private)
- ✅ AWS service quotas (VPC, Elastic IPs)
- ✅ Existing OpenShift resources
- ✅ SSH key configuration
- ✅ OpenShift installer binary
- ⚠️ Conflicting private hosted zones from failed installs

**When to use**:
- Before first installation
- After failed installation (diagnose issues)
- After changing AWS environments
- When troubleshooting DNS/bootstrap failures

**Benefits**:
- Catches issues BEFORE spending 30-45 minutes on installation
- Clear error messages with actionable solutions
- Prevents common mistakes (like domain with leading dot!)

**See**: `docs/AWS-PREREQUISITES-CHECK.md` for detailed documentation

---

### manage-kubeconfig.sh
**Purpose**: Manage kubeconfig files and KUBECONFIG environment variable

**Usage**:
```bash
# Interactive menu
./scripts/manage-kubeconfig.sh

# Quick commands
./scripts/manage-kubeconfig.sh --show      # Show current configuration
./scripts/manage-kubeconfig.sh --clear     # Clear kubeconfig
./scripts/manage-kubeconfig.sh --logout    # Logout from cluster
./scripts/manage-kubeconfig.sh --set       # Set kubeconfig file
```

**What it does**:
- Shows current kubeconfig configuration and cluster connection
- Clears KUBECONFIG environment variable
- Removes kubeconfig files (with backup)
- Logs out from current cluster
- Sets kubeconfig to a specific file
- Checks shell profiles for KUBECONFIG exports

**When to use**:
- When switching between clusters
- When kubeconfig is pointing to an old/deleted cluster
- To clean up after cluster deletion
- To troubleshoot connection issues
- Before installing a new cluster

**Common scenarios**:
```bash
# Stuck with old cluster? Clear it
./scripts/manage-kubeconfig.sh --clear

# Want to see current setup?
./scripts/manage-kubeconfig.sh --show

# Need to logout?
./scripts/manage-kubeconfig.sh --logout
```

---

### cleanup-all.sh
**Purpose**: Comprehensive cleanup of AWS resources (now with quick local cleanup option!)

**Usage**:
```bash
# Interactive menu (recommended)
./scripts/cleanup-all.sh

# Quick local cleanup only (no AWS changes)
./scripts/cleanup-all.sh --local-only
./scripts/cleanup-all.sh -l

# See detailed usage guide
cat scripts/CLEANUP-USAGE.md
```

**What it does**:

**Option 1: Local Cleanup Only** (Quick - seconds)
- Removes `openshift-cluster-install/` directory
- Removes `cluster-info.txt`
- Does NOT touch AWS resources
- Perfect for retrying failed installations

**Option 2: Complete Cleanup** (Thorough - 10-20 minutes)
- Runs `openshift-install destroy` if cluster exists
- Releases unassociated Elastic IPs
- Deletes NAT Gateways and waits for deletion
- Cleans up subnets, security groups, network interfaces
- Removes route tables and internet gateways
- Deletes VPCs
- Handles orphaned resources

**When to use**:
- **Local cleanup**: Failed installation, quick retry, local files only
- **Complete cleanup**: Decommissioning cluster, stopping AWS charges, full reset

---

### create-gpu-machineset.sh
**Purpose**: Create GPU worker nodes dynamically

**Usage**:
```bash
./scripts/create-gpu-machineset.sh
```

**What it does**:
- Detects cluster ID automatically
- Extracts AMI ID and IAM profile from existing workers
- Lists available subnets for selection
- Prompts for GPU instance type (p5.48xlarge, g6e.*)
- Configures storage (default or custom)
- Generates MachineSet YAML
- Applies to cluster

**When to use**:
- After cluster installation
- When you need GPU workers
- To add more GPU capacity
- Works across different clusters

---

### enable-genai-maas.sh
**Purpose**: Enable GenAI Playground and Dashboard features (Model Registry, GenAI Studio, etc.)

**Usage**:
```bash
./scripts/enable-genai-maas.sh
```

**What it does**:
- Installs RHCL/Kuadrant operators
- Installs Leader Worker Set (LWS) operator
- Installs Kueue operator
- Updates DataScienceCluster to v2 API
- Enables GenAI Studio in dashboard
- Enables Model as a Service UI
- Creates GPU hardware profile
- Enables user workload monitoring

**When to use**:
- On existing RHOAI installations
- When you want GenAI Playground
- When you want Model as a Service
- To enable llm-d serving runtime

**Prerequisites**:
- RHOAI must already be installed
- Cluster must have GPU nodes (or plan to add them)

---

### setup-maas.sh
**Purpose**: Set up Model as a Service (MaaS) API infrastructure

**Usage**:
```bash
./scripts/setup-maas.sh
```

**What it does**:
- Installs RHCL/Kuadrant operators (if not present)
- Creates Kuadrant instance
- Configures Authorino with TLS
- Creates GatewayClass
- Deploys MaaS API using kustomize
- Configures audience policy
- Restarts controllers

**When to use**:
- After enabling Dashboard features
- When you want MaaS API endpoints
- For production model serving with authentication
- To enable billing/tracking for models

**Prerequisites**:
- RHOAI installed
- GenAI and Dashboard features enabled
- `jq` installed (`brew install jq`)

**Note**: MaaS API pods may take 2-3 minutes to be ready after deployment.

---

---

### install-rhoai-35.sh
**Purpose**: Full RHOAI 3.5 installation (recommended) — NFD, GPU, Kueue, cert-manager, RHCL, MaaS, llm-d, observability, dashboards

**Usage**:
```bash
./scripts/install-rhoai-35.sh
./scripts/install-rhoai-35.sh --channel stable-3.5
./scripts/install-rhoai-35.sh --deploy-grafana --setup-users --num-users 10
./scripts/install-rhoai-35.sh --enable-external-models --enable-tool-calling
```

**What it does**: Installs all prerequisites, RHOAI operator, MaaS with PostgreSQL, observability stack (COO + Perses + Observe tab dashboards), MLflow (auto-detects PostgreSQL), hardware profiles, and optional Grafana/users/pipelines. Adds two new 3.5 dashboard flags (`--enable-external-models`, `--enable-tool-calling`) on top of the 3.4 feature set.

---

### install-rhoai-34.sh
**Purpose**: Full RHOAI 3.4 installation — NFD, GPU, Kueue, cert-manager, RHCL, MaaS, llm-d, observability, dashboards

**Usage**:
```bash
./scripts/install-rhoai-34.sh
./scripts/install-rhoai-34.sh --channel stable-3.4
./scripts/install-rhoai-34.sh --deploy-grafana --setup-users --num-users 10
```

**What it does**: Installs all prerequisites, RHOAI operator, MaaS with PostgreSQL, observability stack (COO + Perses + Observe tab dashboards), MLflow (auto-detects PostgreSQL), hardware profiles, and optional Grafana/users/pipelines.

---

### setup-letsencrypt-tls.sh
**Purpose**: Automated TLS certificate setup (Let's Encrypt via Route53 DNS-01 or self-signed)

**Usage**:
```bash
./scripts/setup-letsencrypt-tls.sh              # Interactive menu
./scripts/setup-letsencrypt-tls.sh letsencrypt  # Direct Let's Encrypt setup
./scripts/setup-letsencrypt-tls.sh selfsigned   # Direct self-signed setup
./scripts/setup-letsencrypt-tls.sh status       # Show TLS status
```

---

### deploy-dashboards.sh
**Purpose**: Deploy GPU/vLLM monitoring dashboards to OpenShift Observe tab or standalone Grafana

**Usage**:
```bash
./scripts/deploy-dashboards.sh                        # All dashboards to Observe tab
./scripts/deploy-dashboards.sh --method grafana       # Deploy via Grafana Operator
./scripts/deploy-dashboards.sh --dashboard vllm       # Only vLLM dashboard
./scripts/deploy-dashboards.sh --delete               # Remove all dashboards
```

---

### deploy-demo-environment.sh
**Purpose**: Deploy all 17 demo components on an existing RHOAI 3.4+ cluster

**Usage**:
```bash
./scripts/deploy-demo-environment.sh --skip-core
./scripts/deploy-demo-environment.sh --components feast,pipeline,open-webui
./scripts/deploy-demo-environment.sh --list
```

---

## Typical Usage Flow

### Fresh Installation (Recommended)
```bash
# 1. Install RHOAI 3.5 (includes GPU, MaaS, observability)
./scripts/install-rhoai-35.sh

# 2. Create GPU nodes (if not auto-scaled)
./scripts/create-gpu-machineset.sh

# 3. Deploy a model
./scripts/serve-model.sh s3 my-model Qwen/Qwen3-8B-Instruct
```

### Existing RHOAI Installation
```bash
# 1. Enable GenAI and MaaS features
./scripts/enable-genai-maas.sh

# 2. Set up MaaS API
./scripts/setup-maas.sh

# 3. Create GPU nodes if needed
./scripts/create-gpu-machineset.sh
```

### Cleanup
```bash
# Clean up all AWS resources
./scripts/cleanup-all.sh
```

## Notes

- All scripts are designed to be idempotent (safe to run multiple times)
- Scripts check for existing resources before creating
- Most scripts provide detailed output and error messages
- Scripts are meant to be run from the repository root directory

## See Also

- **Main Scripts**: `rhoai-toolkit.sh` (root), `scripts/integrated-workflow-v2.sh`
- **Diagnostics** (in diagnostics/): Tools for troubleshooting
- **Tests** (in tests/): Test scripts for validation
- **Documentation** (in docs/): Detailed guides and troubleshooting

