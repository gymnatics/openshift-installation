# Documentation Index

Documentation for OpenShift AI installation and configuration on AWS.

## Quick Navigation

- [Main README](../README.md) — Project overview and quick start
- [Troubleshooting](TROUBLESHOOTING.md) — All issues and solutions in one place

---

## Guides

Step-by-step instructions for common tasks.

### Installation

| Guide | Description |
|-------|-------------|
| [RHOAI 3.5 Installation](guides/rhoai-3.5/RHOAI-35-INSTALLATION.md) | Full RHOAI 3.5 install guide (recommended) |
| [RHOAI 3.5 What's New](guides/rhoai-3.5/RHOAI-35-WHATS-NEW.md) | Changes from 3.4 to 3.5 (EvalHub GA, MaaS OIDC GA, llm-d flow control GA) |
| [AWS Prerequisites](guides/AWS-PREREQUISITES-CHECK.md) | Pre-installation validation |
| [Using Existing AWS Infrastructure](guides/USING-EXISTING-AWS-INFRASTRUCTURE.md) | Reuse VPCs and subnets |
| [Configuration Reuse](guides/CONFIGURATION-REUSE.md) | Save and reuse install settings |
| [Kubeconfig Management](guides/KUBECONFIG-MANAGEMENT.md) | Manage cluster connections |

### GPU & Hardware

| Guide | Description |
|-------|-------------|
| [GPU ResourceFlavor Configuration](reference/GPU-RESOURCEFLAVOR-CONFIGURATION.md) | GPU tolerations and Kueue ResourceFlavor setup |
| [Hardware Profile Setup](guides/HARDWARE-PROFILE-SETUP.md) | Create hardware profiles for RHOAI 3.x |

### Model Deployment

| Guide | Description |
|-------|-------------|
| [Interactive Model Deployment](guides/INTERACTIVE-MODEL-DEPLOYMENT.md) | Deploy models via interactive menu |
| [llm-d Setup](guides/LLMD-SETUP-GUIDE.md) | Set up llm-d serving runtime |
| [Tool Calling](guides/TOOL-CALLING-GUIDE.md) | Enable function calling in models |
| [Model Registry](guides/MODEL-REGISTRY.md) | Model versioning and lifecycle |
| [GenAI Playground](guides/GENAI-PLAYGROUND-INTEGRATION.md) | Add models to playground |

### MaaS (Models as a Service)

| Guide | Description |
|-------|-------------|
| [MaaS Serving Runtimes](guides/MAAS-SERVING-RUNTIMES.md) | Which runtimes work with MaaS |
| [MaaS Policy Enforcement](guides/MAAS-POLICY-ENFORCEMENT.md) | Configure MaaS authentication and rate limiting |
| [MaaS Demo](guides/MAAS-DEMO-GUIDE.md) | Running the MaaS demo |

### Observability & Monitoring

| Guide | Description |
|-------|-------------|
| [OpenShift Observe Dashboards](guides/OPENSHIFT-OBSERVE-DASHBOARDS.md) | Add DCGM/vLLM dashboards to OpenShift Observe tab (ConfigMap approach) |

### Security & Governance

| Guide | Description |
|-------|-------------|
| [RHCL + NeMo Guardrails Architecture](guides/RHCL-GUARDRAILS-ARCHITECTURE.md) | RHCL (MaaS access control) + TrustyAI NeMo Guardrails |
| [AI Agent Security & Governance](guides/AI-AGENT-SECURITY-GOVERNANCE.md) | Guardrails, access controls, data protection |

### MCP & Tool Calling

| Guide | Description |
|-------|-------------|
| [MCP Catalog Setup](guides/MCP-CATALOG-SETUP.md) | Install MCP Lifecycle Operator + enable catalog in dashboard |
| [MCP Servers](guides/MCP-SERVERS.md) | Model Context Protocol for tool calling |
| [MCP Server Setup](guides/MCP-SERVER-SETUP.md) | Configure MCP servers |
| [OCP MCP Server Deployment](guides/OCP-MCP-SERVER-DEPLOYMENT.md) | Deploy MCP servers on OpenShift |

### Workshops

| Guide | Description |
|-------|-------------|
| [Model Deployment Workshop](guides/RHOAI-MODEL-DEPLOYMENT-WORKSHOP.md) | Hands-on: deploy models via the UI + test with AI Playground |
| [LLMOps GitOps Demo](guides/LLMOPS-GITOPS-DEMO.md) | Customer demo: deploy LLMs with ArgoCD GitOps (dev/staging/prod) |

### Demo Environment

| Guide | Description |
|-------|-------------|
| [Demo Environment](guides/DEMO-ENVIRONMENT.md) | Full demo environment — 17 components, GPU requirements |

### End-to-End Setup Guides

| Guide | Description |
|-------|-------------|
| [Setup Guide (English)](guides/setup-guide_EN.md) | Full walkthrough from AWS install through RHOAI 3.4 |
| [Setup Guide (Korean)](guides/setup-guide_KO.md) | Korean translation of the setup guide |

---

## Bugs & Known Issues

Active bug reports for RHOAI 3.4 (MaaS TLS/Authorino mechanisms are unchanged in 3.5, so these likely still apply):

| Report | Description |
|--------|-------------|
| [MaaS Bugs (RHOAI 3.4)](bugs/maas-bugs-rhoai-34.md) | Tenant `gatewayRef` + Authorino CEL issues |
| [EvalHub Bugs (RHOAI 3.4)](bugs/evalhub-bugs-rhoai-34.md) | LMEval / EvalHub TP issues |
| [EvalHub Dashboard Namespace](bugs/evalhub-dashboard-namespace-lookup.md) | CR must be in `redhat-ods-applications` |
| [Authorino CEL MetricLabels Bug](bugs/authorino-cel-metriclabels-bug.md) | Breaks MaaS Usage dashboard labels |
| [MaaS Token Rate Limit Span Buffer](bugs/maas-token-ratelimit-span-buffer-bug.md) | WasmPlugin span buffer saturation |

---

## Reference

Technical reference documentation.

| Document | Description |
|----------|-------------|
| [Serving Runtime Comparison](reference/SERVING-RUNTIME-COMPARISON.md) | Compare vLLM, llm-d, and other runtimes |
| [KServe Deployment Modes](reference/KSERVE-DEPLOYMENT-MODES.md) | RawDeployment vs Serverless |
| [GPU ResourceFlavor Configuration](reference/GPU-RESOURCEFLAVOR-CONFIGURATION.md) | Kueue ResourceFlavor setup for GPU tolerations |
| [OS Compatibility](reference/OS-COMPATIBILITY.md) | macOS/Linux compatibility layer (`os-compat.sh`) |

---

## Archived — RHOAI 3.4

Kept for reference if running a 3.4 cluster. See `docs/guides/rhoai-3.4/`.

| Guide | Description |
|-------|-------------|
| [RHOAI 3.4 Installation](guides/rhoai-3.4/RHOAI-34-INSTALLATION.md) | Full RHOAI 3.4 install guide |
| [RHOAI 3.4 What's New](guides/rhoai-3.4/RHOAI-34-WHATS-NEW.md) | Changes from 3.3 to 3.4 (MaaS GA, NeMo GA, AutoML/AutoRAG) |
| [RHOAI 3.4 Manual Installation](guides/rhoai-3.4/RHOAI-34-MANUAL-INSTALLATION-GUIDE.md) | Step-by-step with all YAMLs — Path A (no MaaS) and Path B (full MaaS) |

## Archived — RHOAI 3.3

Kept for reference if running a 3.3 cluster. See `docs/guides/rhoai-3.3/`.

| Guide | Description |
|-------|-------------|
| [RHOAI 3.3 Installation](guides/rhoai-3.3/RHOAI-33-INSTALLATION.md) | Full RHOAI 3.3 install guide |
| [RHOAI 3.3 What's New](guides/rhoai-3.3/RHOAI-33-WHATS-NEW.md) | Changes from 3.2 to 3.3 |
| [MaaS Setup (3.3)](guides/rhoai-3.3/MAAS-SETUP-STEP-BY-STEP.md) | Tier-based MaaS setup for RHOAI 3.3 |
| [Manual Installation Guide (3.3)](guides/rhoai-3.3/RHOAI-MANUAL-INSTALLATION-GUIDE.md) | Step-by-step with all YAMLs for 3.3 |

---

## Troubleshooting

All troubleshooting is consolidated in [TROUBLESHOOTING.md](TROUBLESHOOTING.md), covering:
- OpenShift installation issues
- RHOAI component problems (Kueue, LWS, Authorino, dashboard)
- Model deployment (hardware profiles, vLLM args)
- MaaS / rate limiting
- macOS compatibility

---

## External Resources

- [RHOAI 3.5 Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5)
- [OpenShift Documentation](https://docs.openshift.com)
- [Kueue Documentation](https://kueue.sigs.k8s.io/)
- [KServe Documentation](https://kserve.github.io/website/)
- [vLLM Documentation](https://docs.vllm.ai/)

---

**Last Updated**: September 2026
**RHOAI Version**: 3.5
**OpenShift Version**: 4.19+ (4.19-4.20 per RHOAI 3.5 documented support matrix)
