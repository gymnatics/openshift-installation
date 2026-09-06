# OpenShift AI Installation Toolkit

A comprehensive toolkit for installing and configuring **OpenShift** with **Red Hat OpenShift AI (RHOAI) 3.x** on AWS, including GPU support, Model as a Service (MaaS), and GenAI capabilities.

> **Latest:** RHOAI 3.5 is now supported. See [What's New in RHOAI 3.5](docs/guides/rhoai-3.5/RHOAI-35-WHATS-NEW.md) for details.
> EvalHub, external OIDC auth for MaaS, Automated Red Teaming, and llm-d priority-based flow control are now GA.
> MCP gateway/lifecycle operators, MaaS multi-tenancy, and AutoGluon runtime are new Technology Preview features.

> **Resolved:** The toolkit menu now correctly routes both **`stable-3.5`** and the rolling **`stable-3.x`** channel
> (which currently resolves to RHOAI 3.5.0 GA) to the full `install-rhoai-35.sh` installation flow.

## Quick Start

```bash
./rhoai-toolkit.sh
```

This single command provides an interactive menu to:
- Install OpenShift cluster on AWS
- Set up RHOAI with all components
- Create GPU nodes
- Deploy AI models
- Configure MaaS API

---

## Features

| Feature | Description |
|---------|-------------|
| **One-Click Setup** | Interactive menu-driven installation |
| **GPU Support** | Automated GPU MachineSet creation (g6e, p5 instances) |
| **RHOAI 3.x** | Full RHOAI installation with Kueue, LWS, and Hardware Profiles |
| **Model Serving** | vLLM, vLLM-Omni (multimodal), llm-d, NVIDIA NIM, and community runtimes |
| **MaaS API** | Model as a Service with authentication via Kuadrant |
| **Observability** | Auto-configured COO + Perses + Observe tab dashboards (DCGM, vLLM) |
| **Let's Encrypt TLS** | Automated wildcard certificates via Route53 DNS-01 |
| **MCP Servers** | 8 deployable MCP servers with Gateway API routing |
| **HuggingFace to S3** | Download models from HuggingFace to MinIO for deployment |
| **GenAI Playground** | Interactive model testing interface |
| **19 Demo Apps** | Banking, Open WebUI, LlamaStack, Guardrails, NIM, Pipelines, and more |
| **Cross-Platform** | Works on macOS and Linux |

---

## Prerequisites

- **AWS Account** with appropriate permissions
- **OpenShift Pull Secret** from [console.redhat.com](https://console.redhat.com/openshift/install/pull-secret)
- **AWS CLI** configured (`aws configure`)
- **oc CLI** (OpenShift client)
- **Route53 Hosted Zone** for your domain

---

## Repository Structure

```
├── rhoai-toolkit.sh              # Main interactive menu (sources lib/)
├── scripts/                      # 50+ utility scripts
│   ├── install-rhoai-35.sh       # RHOAI 3.5 full installation (recommended)
│   ├── install-rhoai-34.sh       # RHOAI 3.4 full installation
│   ├── install-rhoai-33.sh       # RHOAI 3.3 full installation
│   ├── install-rhoai-minimal.sh  # Minimal RHOAI install
│   ├── create-gpu-machineset.sh  # GPU node creation (AWS)
│   ├── setup-maas.sh             # MaaS API gateway (version-aware)
│   ├── serve-model.sh            # Model deployment (vLLM/llm-d)
│   ├── deploy-nim.sh             # NVIDIA NIM deployment (NGC/NVAIE)
│   ├── setup-letsencrypt-tls.sh  # Let's Encrypt / self-signed TLS automation
│   ├── deploy-dashboards.sh      # GPU/vLLM dashboards (Observe tab + Grafana)
│   ├── deploy-demo-environment.sh # Deploy all 17 demo components
│   ├── setup-users.sh            # User management (htpasswd + groups)
│   └── cleanup-all.sh            # Resource cleanup
│
├── lib/
│   ├── functions/                # Reusable bash functions (15 modules)
│   ├── menus/                    # Interactive menu handlers (12 files)
│   ├── manifests/                # Kubernetes YAML templates
│   │   ├── rhoai/                # RHOAI operator, DSC, hardware profiles
│   │   ├── monitoring/           # Observe dashboards, Grafana, Perses
│   │   ├── mcp/                  # MCP server deployments + Gateway routing
│   │   ├── tls/                  # Let's Encrypt + wildcard cert templates
│   │   └── ...                   # maas, rhcl, operators, templates, etc.
│   └── utils/                    # Utility libraries (os-compat, colors, etc.)
│
├── demo/                         # 19 demo apps (each with deploy.sh)
├── docs/
│   ├── guides/                   # How-to guides
│   ├── reference/                # Technical reference
│   └── TROUBLESHOOTING.md        # Common issues and solutions
│
└── diagnostics/                  # Diagnostic scripts
```

---

## Usage

### Install RHOAI 3.5 (Recommended)

```bash
# Direct script — full automated install
./scripts/install-rhoai-35.sh

# Or interactive menu — select option 1
./rhoai-toolkit.sh

# Makefile one-liner
make setup-rhoai-35
```

The interactive menu puts the most common options first:
1. **Install RHOAI 3.5** — Recommended for most users
2. **Workshop Demo Setup** — RHOAI 3.5 + OpenWebUI for hands-on workshops
3. **Complete Setup** — Full OpenShift + RHOAI + GPU + MaaS from scratch
4. **Minimal Setup** — Choose which operators to install

### Common Script Flags (3.5)

```bash
# With specific RHOAI channel
./scripts/install-rhoai-35.sh --channel stable-3.5

# With external PostgreSQL for MaaS (production)
./scripts/install-rhoai-35.sh --postgres-connection 'postgresql://user:pass@host:5432/db?sslmode=require'

# Skip if prerequisites already installed
./scripts/install-rhoai-35.sh --skip-prerequisites --skip-node-scaling

# Enable TP features
./scripts/install-rhoai-35.sh --enable-vllm-maas --enable-observability

# Enable new 3.5 dashboard features
./scripts/install-rhoai-35.sh --enable-external-models --enable-tool-calling

# Deploy standalone Grafana with GPU/vLLM dashboards
./scripts/install-rhoai-35.sh --deploy-grafana

# Set up TLS certificates (standalone)
./scripts/setup-letsencrypt-tls.sh
```

### Individual Operations

```bash
# Create GPU nodes
./scripts/create-gpu-machineset.sh

# Set up MaaS API
./scripts/setup-maas.sh

# Deploy a model
./scripts/serve-model.sh

# Setup model storage (MinIO) and download from HuggingFace
./scripts/setup-model-storage.sh
./scripts/download-model.sh s3 Qwen/Qwen3-8B-Instruct

# Clean up resources
./scripts/cleanup-all.sh
```

---

## Supported Serving Runtimes

| Runtime | Use Case | CR Type | MaaS |
|---------|----------|---------|------|
| **vLLM (Red Hat)** | Text LLMs (default) | InferenceService | No |
| **vLLM (Community)** | Newer models (Qwen3.5, etc.) | InferenceService | No |
| **vLLM-Omni** | Multimodal: FLUX, SD3, audio | InferenceService | No |
| **llm-d** | MaaS, multi-replica | LLMInferenceService | Yes |

---

## Quick Reference

### Common Commands

```bash
# Full installation (recommended)
./scripts/install-rhoai-35.sh --channel stable-3.5

# Or interactive menu
./rhoai-toolkit.sh

# Previous versions
./scripts/install-rhoai-34.sh
./scripts/install-rhoai-33.sh

# Add GPU nodes
./scripts/create-gpu-machineset.sh

# Create hardware profile
./scripts/create-hardware-profile.sh <namespace>

# Fix GPU tolerations
./scripts/fix-gpu-resourceflavor.sh

# Setup MaaS
./scripts/setup-maas.sh

# Clean up everything
./scripts/cleanup-all.sh
```

### Verification

```bash
# Check all operators
oc get csv -A | grep -E "nfd|gpu|kueue|lws|rhcl|rhods"

# Check RHOAI
oc get datasciencecluster

# Check hardware profiles
oc get hardwareprofiles -n redhat-ods-applications

# Check GPU nodes
oc get nodes -l nvidia.com/gpu.present=true

# Check MaaS (3.3+)
oc get gateway -n openshift-ingress

# Restart components
oc delete pod -n redhat-ods-applications -l app=odh-model-controller
oc delete pod -n kuadrant-system -l control-plane=controller-manager
```

### Operator Logs

```bash
oc logs -n redhat-ods-operator -l name=rhods-operator --tail=50
oc logs -n nvidia-gpu-operator -l app=gpu-operator --tail=50
oc logs -n kuadrant-system -l control-plane=controller-manager --tail=50
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common issues and solutions |
| [docs/guides/](docs/guides/) | Step-by-step guides |
| [docs/reference/](docs/reference/) | Technical reference |

### Key Guides

- [RHOAI 3.5 Installation](docs/guides/rhoai-3.5/RHOAI-35-INSTALLATION.md) (recommended)
- [What's New in RHOAI 3.5](docs/guides/rhoai-3.5/RHOAI-35-WHATS-NEW.md)
- [OpenShift Observe Dashboards](docs/guides/OPENSHIFT-OBSERVE-DASHBOARDS.md)
- [Hardware Profile Setup](docs/guides/HARDWARE-PROFILE-SETUP.md)
- [GPU ResourceFlavor Configuration](docs/reference/GPU-RESOURCEFLAVOR-CONFIGURATION.md)
- [Tool Calling](docs/guides/TOOL-CALLING-GUIDE.md)
- [llm-d Setup](docs/guides/LLMD-SETUP-GUIDE.md)
- [RHOAI 3.4 Installation](docs/guides/rhoai-3.4/RHOAI-34-INSTALLATION.md) (archived)
- [RHOAI 3.3 Installation](docs/guides/rhoai-3.3/RHOAI-33-INSTALLATION.md) (archived)

---

## Requirements

| Tool | Version | Purpose |
|------|---------|---------|
| `oc` | 4.14+ | OpenShift CLI |
| `aws` | 2.x | AWS CLI |
| `jq` | 1.6+ | JSON processing |
| `yq` | 4.x | YAML processing |

---

## Contributing

1. Scripts should use the OS compatibility layer (`lib/utils/os-compat.sh`)
2. Follow existing code style and patterns
3. Update documentation when adding features
4. Test on both macOS and Linux

---

## External Resources

- [RHOAI 3.5 Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5)
- [RHOAI 3.5 MaaS Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/govern_llm_access_with_models-as-a-service)
- [RHCL 1.3 Install Guide](https://docs.redhat.com/en/documentation/red_hat_connectivity_link/1.3/html-single/installing_on_openshift_container_platform/index)
- [RHOAI Supported Configurations](https://access.redhat.com/articles/rhoai-supported-configs)
- [OpenShift Documentation](https://docs.openshift.com)
- [Kueue Documentation](https://kueue.sigs.k8s.io/)
- [KServe Documentation](https://kserve.github.io/website/)

---

**License:** Apache License 2.0
