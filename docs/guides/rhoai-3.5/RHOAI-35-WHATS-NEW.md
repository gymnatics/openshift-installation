# What's New in RHOAI 3.5

> Official documentation: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5

## GA Promotions (from Tech Preview in 3.4)

### EvalHub — Now GA
EvalHub (the Red Hat AI evaluation stack) is Generally Available, with a documented API versioning scheme, a breaking-change policy, full Red Hat support, and must-gather tooling.

- Client SDK and CLI (`eval-hub-sdk`) — Adapter SDK, job submission, provider discovery, result retrieval
- Per-tenant deployment (`spec.tenancy: single`) — namespace admins can deploy their own EvalHub instance without cluster-admin involvement
- EvalCard generation for evaluation runs (schema-validated JSON, stored as MLflow/OCI artifact)
- Automatic Prometheus `ServiceMonitor` creation
- Local development mode (`pip install "eval-hub-sdk[server]"`) — run the full loop on a laptop, no cluster required

### External OIDC Authentication for MaaS — Now GA
Previously Technology Preview in 3.4. You can now authenticate MaaS users against an external OpenID Connect identity provider instead of requiring OpenShift accounts for every user, including OIDC group-to-subscription mapping.

### Automated Red Teaming (Garak) — Now GA
Proactive model vulnerability/safety scanning. Adds OpenAI Responses API endpoints, multilingual red teaming, multiclass judge safety evaluation, parallelized execution, and disconnected (air-gapped) support.

### Responses API on OGX — Now GA
The OpenAI-compatible Responses API on OGX (formerly Llama Stack) is now GA, enabled by default in the runtime `config.yaml`.

### Priority-based Flow Control for llm-d — Now GA
`InferenceObjective` resources define priority tiers; saturation detection and per-band queuing policies ensure latency-sensitive requests are served ahead of batch traffic.

**Breaking changes if you used the 3.4 Technology Preview:**
- API group renamed: `inference.networking.x-k8s.io` → `llm-d.ai` (update all `InferenceObjective`/`EndpointPickerConfig` resources)
- Metrics prefix renamed: `inference_extension_` → `llm_d_epp_` (update Prometheus dashboards/alerts)
- Saturation detector config moved from top-level `saturationDetector` to `flowControl.saturationDetector` (plugin-reference pattern)

**Additional breaking changes confirmed via live testing against a real RHOAI 3.5.0 GA cluster
(not called out in the public release notes as of this writing):**
- `OdhDashboardConfig`'s `spec.dashboardConfig.maasAuthPolicies` field is now **rejected** by
  CEL validation (`DEPRECATED: spec.dashboardConfig.maasAuthPolicies must be removed or left
  unchanged`). Any script/GitOps config that sets this field on a fresh install will fail the
  patch. Omit it entirely — MaaS governance UI access is now gated by `genAiStudio`/`modelAsService` alone.
- `DataScienceCluster`'s `spec.components.kserve.modelsAsService` field is now deprecated in
  favor of `spec.components.aigateway.modelsAsAService` (the old field still works — "respected
  at least through 3.6" per the operator's own deprecation warning — but clearing it to
  `Removed` blocks re-enabling it via the old path).

## Renamed: Llama Stack → OGX

Starting in 3.5 EA1, "Llama Stack" is renamed to "OGX" throughout the product and docs. Manual migration steps apply if you have existing Llama Stack configuration. The `llamastackoperator` DataScienceCluster component key is unchanged as of this writing.

## New Features

### `rhai-cli` Migration Guide (2.25.9+ → 3.5)
A new migration guide walks admins through pre-upgrade assessment, side-by-side vs. in-place migration, Kueue management-state prerequisites, and component-specific `rhai-cli migrate` actions (Kueue/RHBOK, AI Pipelines, Model Serving, Workbenches, TrustyAI, Training, OGX, Ray). After upgrading, move off the `support-required-upgrade-3.5` channel to a normal channel (`stable-3.5`, `stable-3.x`, or `eus-3.5`).

### GPU-Accelerated MLServer Runtime
New `mlserver-onnx-gpu` cluster serving runtime and container image for NVIDIA GPU-accelerated predictive ML inference (separate from the unchanged CPU MLServer runtime).

### DiffusionGemma (dLLM) Model Support
First discrete diffusion LLM supported for KServe model serving.

### Kueue Scheduling Visibility + Self-Managed Queues
- Workbenches overview shows Kueue-derived states (Queued, Starting, Preempted, Evicted, Requeued) with a redesigned startup progress modal
- New boolean flag on the Kueue DataScienceCluster component to disable automatic default `ClusterQueue`/`LocalQueue` creation, so admins can manage queues entirely via GitOps

### Inference-Aware Pod Lifecycle for llm-d
Rolling updates, scale-downs, and node maintenance no longer drop active inference requests; pods that are still loading model weights are excluded from routing.

### Distributed Inference with llm-d on Cross-Kubernetes Platforms
GA on AKS, CoreWeave Kubernetes Service (CKS), and OpenShift, including Istio as the supported gateway and the Gateway API Inference Extension (GAIE).

### Observability Dashboards for llm-d — Installed by Default
Perses-based dashboards (KV-cache utilization, queue depth, TTFT, throughput, EPP/WVA metrics) are created automatically wherever llm-d is deployed (requires User Workload Monitoring).

### Canary Rollout for KServe RawDeployment
Progressive model rollouts by splitting traffic between primary and canary deployments within the same `InferenceService`, via Route `alternateBackends` or Gateway API weighted `HTTPRoute` backends. Fixed replica count — no HPA/KEDA autoscaling for canary.

### MLflow Integration for AI Pipelines / Kubeflow Trainer / Workbenches
Experiment runs from pipelines, Kubeflow Trainer jobs, and workbenches are automatically tracked by a dedicated MLflow server, reducing context switching. Includes age-based trace archival to S3-compatible storage at scale.

### GPU Topology and Utilization Dashboard
New Infrastructure page: accelerator count, compute/memory utilization, Kueue cohort overview, hardware inventory by model, borrowing/lending trends (requires Kueue).

### MaaS Body-Based Model Routing
Standard OpenAI `/v1/chat/completions` requests with the model name in the body now work directly through MaaS (drop-in compatible with `openai`, LangChain, LlamaIndex, OpenWebUI). Legacy path-based routing still supported.

### Unified MaaS Governance Page
Settings → Subscriptions and Settings → Authorization Policies are merged into a single Settings → **MaaS governance** page with tabs and expandable Groups/Models columns.

### KubeRay Upgraded to 1.6.x
Existing `RayCluster`/`RayJob` workloads continue to work without changes.

## New Technology Preview Features

- **MCP gateway Operator** — external prerequisite for MCP management workflows; independently lifecycle-managed
- **MCP Lifecycle Operator** — runtime infrastructure for MCP servers, auto-deployed with RHOAI, powers the MCP Catalog
- **MCP Catalog support-tier labels** — Red Hat Supported / Partner Supported / Community Supported badges
- **Unified generative AI model deployment wizard** — single "Deploy model" entry point replacing separate legacy/llm-d/MaaS-vLLM workflows
- **MaaS multi-tenancy** — per-tenant gateway + identity isolation via a single CR; gateway/IdP are external prerequisites
- **Multi-provider API passthrough for MaaS external models** — native Anthropic Messages API / OpenAI Responses API passthrough
- **AutoGluon serving runtime** — pre-configured runtime for AutoML `TabularPredictor` models
- **Docling SDK/Serve GPU container images** — `docling-sdk-cuda-ubi9`, `docling-serve-cuda-ubi9` for GPU-accelerated document conversion
- **Batch inference for llm-d** — OpenAI-compatible `/v1/batches` API, scheduled at low priority
- **View external model endpoints in the dashboard** — enable via `spec.dashboardConfig.externalModels: true` on `OdhDashboardConfig`
- **Validated tool-calling configuration in Model Catalog** — enable via `spec.dashboardConfig.toolCalling: true`
- **NeMo Guardrails + MCP Gateway integration** — enforce guardrails on agent tool calls at the gateway layer
- **Gen AI Studio**: multimodal playground (image/audio), prompt management with template variables, chat metrics/tracing panel, global prompt registry namespaces
- **CPU-only AutoRAG** — evaluate RAG pipelines without GPUs (lightweight foundation/embedding models)
- **Self-service Subscriptions tab** for MaaS users (Gen AI Studio → API keys → Subscriptions)
- **Safety and Security Insights tab** in the Red Hat AI Model Catalog (Garak-based adversarial scan results)

## Enhancements

- Cold-start load time and vRAM metrics in the Model Catalog, filterable/sortable
- Non-cluster-admin access to Perses-based dashboards, scoped to authorized namespaces
- View the running vLLM version for llm-d deployments from the dashboard
- Option to disable built-in TLS on llm-d pods (`spec.tls.enabled: false`) when a service mesh already provides mTLS
- 2025.2 workbench/pipeline runtime images retained (marked outdated) alongside new Red Hat Python index defaults, for upgrade transition
- Targeted vLLM access-log filtering (`--disable-access-log-for-endpoints /health,/metrics,/ping`) replacing the blanket log-disable from 3.4, restoring inference request visibility
- Feature store ↔ workbench bidirectional visibility in the dashboard
- Hide default workbench images from the selection dropdown (Settings → Notebook images)
- OAuth proxy sidecar resources configurable directly via `spec.components.kserve.oauthProxy.resources` on the DataScienceCluster (no need to flip to `Unmanaged`)
- `SparkApplication` batch engine for Feast (Kubeflow Spark Operator) — `batch_engine.type: spark_application`
- Custom role creation UI for workbenches in data science projects (`roleManagement` enabled by default)
- Guided "Welcome to OpenShift AI 3.5" dashboard tour, adaptive to enabled features

## MaaS Architecture Changes (3.4 → 3.5)

| Aspect | 3.4 | 3.5 |
|--------|-----|-----|
| External OIDC auth | Technology Preview | **GA** |
| Model routing | Path-based only | Path-based **+ OpenAI-compatible body-based routing** |
| Governance UI | Separate Subscriptions / Authorization Policies pages | **Unified MaaS governance page** (tabbed) |
| Multi-tenancy | N/A | Technology Preview (per-tenant gateway + identity isolation) |
| External model API passthrough | N/A | Technology Preview (Anthropic Messages API, OpenAI Responses API) |
| MaaS TLS (Authorino) | OpenShift service-ca | **Unchanged** |
| RHCL requirement | v1.2+ | **Unchanged** (v1.2+) |
| Dashboard flags | `modelAsService`, `maasAuthPolicies`, `genAiStudio`, `vLLMDeploymentOnMaaS` (TP), `observabilityDashboard` (TP) | `maasAuthPolicies` **removed** — rejected by CEL validation (`must be removed or left unchanged`), confirmed on a live 3.5.0 GA cluster and not documented in public release notes; + `externalModels` (TP), `toolCalling` |

## Installation

Use the toolkit:
```bash
# Interactive
./rhoai-toolkit.sh   # Select option 1 for RHOAI 3.5

# Direct
./scripts/install-rhoai-35.sh

# With specific channel
./scripts/install-rhoai-35.sh --channel stable-3.5

# With new 3.5 dashboard flags (Technology Preview / new)
./scripts/install-rhoai-35.sh --enable-external-models --enable-tool-calling

# Makefile
make setup-rhoai-35
```

See [RHOAI-35-INSTALLATION.md](RHOAI-35-INSTALLATION.md) for full details.
