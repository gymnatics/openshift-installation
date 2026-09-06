# RHOAI 3.5 Installation Guide

## Prerequisites

- OpenShift Container Platform 4.19+ (4.20+ recommended for llm-d)
  - Official RHOAI 3.5 docs list the validated range as OCP 4.19–4.20. Newer OCP
    versions (e.g. 4.21+) are outside the documented support matrix but the
    toolkit's prerequisite check only enforces the `>= 4.19` lower bound.
- `oc` CLI logged in with cluster-admin privileges
- AWS infrastructure (for GPU MachineSet creation)

## Quick Start

```bash
# Full automated install (recommended)
./scripts/install-rhoai-35.sh

# With specific channel
./scripts/install-rhoai-35.sh --channel stable-3.5

# Skip prerequisites if already installed
./scripts/install-rhoai-35.sh --skip-prerequisites

# Enable vLLM runtime for MaaS (Technology Preview)
./scripts/install-rhoai-35.sh --enable-vllm-maas

# Enable new 3.5 dashboard features
./scripts/install-rhoai-35.sh --enable-external-models --enable-tool-calling

# Skip admin user creation (if you already have an identity provider)
./scripts/install-rhoai-35.sh --skip-admin-user
```

## Script Flags

| Flag                          | Description                                                                                      |
| ----------------------------- | ------------------------------------------------------------------------------------------------ |
| `--skip-prerequisites`        | Skip NFD, GPU, Kueue, cert-manager                                                               |
| `--skip-rhcl`                 | Skip RHCL/Kuadrant (no MaaS/llm-d auth)                                                          |
| `--skip-maas`                 | Skip MaaS configuration                                                                          |
| `--skip-node-scaling`         | Skip worker/GPU node scaling                                                                     |
| `--no-llmd`                   | Don't install LWS or configure llm-d Gateway                                                     |
| `--enable-vllm-maas`          | Enable vLLM runtime for MaaS (Technology Preview)                                                |
| `--enable-observability`      | Enable MaaS observability dashboard (Technology Preview)                                         |
| `--enable-external-models`    | Enable external model endpoints view in AI hub (Technology Preview, new in 3.5)                  |
| `--enable-tool-calling`       | Enable validated tool-calling configuration display on Model Catalog cards (new in 3.5)          |
| `--deploy-grafana`            | Deploy standalone Grafana instance with GPU/vLLM dashboards                                      |
| `--postgres-connection <url>` | External PostgreSQL URL for MaaS (format: `postgresql://user:pass@host:5432/db?sslmode=require`) |
| `--skip-maas-db`              | Skip MaaS PostgreSQL setup entirely                                                              |
| `--skip-admin-user`           | Skip creating the htpasswd admin user (script prompts by default)                                |
| `--channel <channel>`         | RHOAI channel (e.g., `stable-3.5`, `stable-3.x`)                                                 |
| `--domain <domain>`           | Cluster domain                                                                                   |
| `--timeout <seconds>`         | Operator wait timeout (default: 600)                                                             |
| `--setup-users`               | Create demo users (user1..userN) with htpasswd + groups                                          |
| `--num-users <N>`             | Number of demo users (default: 5, implies `--setup-users`)                                       |
| `--admin-group <name>`        | Admin group name (default: `rhods-admins`). user1 goes here.                                     |
| `--user-group <name>`         | Regular user group name (default: `rhods-users`). user2+ go here.                                |
| `--user-password <pw>`        | Password for all demo users (default: `openshift`)                                               |

> **Channel note:** Prefer `stable-3.5` (or `stable-3.x`, which currently resolves
> to 3.5.0 GA) over `fast-3.x`. The `fast-3.x` fast-track channel has been observed
> pointing to an older CSV on some catalogs/clusters — always verify the resolved
> CSV version before relying on it: `oc get packagemanifest rhods-operator -n
> openshift-marketplace -o jsonpath='{range .status.channels[*]}{.name}{" -> "}{.currentCSV}{"\n"}{end}'`

---

## What's Installed Automatically

The following are installed **unconditionally** by `install-rhoai-35.sh` (no flags needed):

- **Observability stack**: COO (Cluster Observability Operator) + UIPlugins + Perses server + Thanos proxy secret. This fixes the "Service Unavailable" error on the RHOAI Observability dashboard.
- **Observe tab dashboards**: NVIDIA DCGM, vLLM Performance, and vLLM Advanced dashboards deployed as ConfigMaps to the OpenShift Observe tab (zero extra pods).
- **MLflow with PostgreSQL auto-detection**: If MaaS PostgreSQL is deployed, MLflow automatically uses it as its backend instead of SQLite.
- **Let's Encrypt auto-provisioning**: If no ClusterIssuer exists and `setup-letsencrypt-tls.sh` is present, gateway TLS setup will attempt to auto-provision certificates.

---

## Installation Steps

The `install-rhoai-35.sh` script performs these steps in order. Each section includes the manual CLI commands if you need to run them by hand. Most steps are unchanged from 3.4 — differences are called out explicitly.

### 1. Prerequisites Check

- Verifies `oc` CLI, cluster login, cluster-admin
- Checks OCP version >= 4.19 (warns if < 4.20 for llm-d; informational note if > 4.20, since that's outside the documented 3.5 support matrix)

### 2. Node Scaling

- Scales workers to >= 2
- Creates GPU MachineSet (g6e.xlarge) if none exists

### 3. Prerequisite Operators

These operators must be installed before RHOAI. They provide GPU scheduling, certificate management, and multi-node inference support. Unchanged from 3.4.

| Operator                     | Namespace                | Purpose for MaaS                                     |
| ----------------------------- | ------------------------ | ---------------------------------------------------- |
| Node Feature Discovery (NFD) | `openshift-nfd`          | Detects GPU hardware on nodes                        |
| NVIDIA GPU Operator          | `nvidia-gpu-operator`    | GPU drivers, device plugin, monitoring               |
| Kueue                        | `openshift-operators`    | Workload scheduling and quota management             |
| cert-manager                 | `cert-manager-operator`  | TLS certs for Kueue, LWS, and gateway HTTPS listener |
| LeaderWorkerSet (LWS)        | `openshift-lws-operator` | Multi-node inference for llm-d                       |

**Manual Commands**

```bash
# Each operator: create Namespace, OperatorGroup, Subscription
# Example for cert-manager:
oc create namespace cert-manager-operator
oc apply -f lib/manifests/operators/certmanager-operatorgroup.yaml
oc apply -f lib/manifests/operators/certmanager-subscription.yaml

# Wait for each operator CSV to reach Succeeded:
oc get csv -n cert-manager-operator -w
```

### 4. RHCL (Red Hat Connectivity Link) + Service Mesh

RHCL provides Authorino (authentication) and rate limiting for the MaaS gateway. Service Mesh 3.x (Sail/Istio) is auto-installed as an OLM dependency of the RHOAI operator. The v1.2+ requirement is unchanged from 3.4, so the toolkit reuses the same `rhcl-operator-34.yaml` subscription manifest.

| Resource            | Namespace             | Why                                          |
| -------------------- | --------------------- | --------------------------------------------- |
| RHCL Subscription   | `openshift-operators` | AllNamespaces install mode (OLM requirement) |
| Kuadrant CR         | `kuadrant-system`     | Creates Authorino, Limitador in dedicated ns |
| Authorino           | `kuadrant-system`     | Auto-created by Kuadrant CR                  |
| Service Mesh (Sail) | `openshift-ingress`   | Auto-installed as RHOAI OLM dependency       |

> **Warning:** OLM may set InstallPlan approval to Manual for RHCL dependencies. The toolkit auto-approves pending InstallPlans for RHCL, Service Mesh, and Sail operators.

**Manual Commands**

```bash
# 1. Install RHCL operator (same manifest as 3.4 — RHCL version requirement unchanged)
oc apply -f lib/manifests/rhcl/rhcl-operator-34.yaml

# 2. Approve any pending InstallPlans
oc get installplan -n openshift-operators
oc patch installplan <name> -n openshift-operators \
  --type=merge -p '{"spec":{"approved":true}}'

# 3. Wait for RHCL CSV
oc get csv -n openshift-operators | grep rhcl

# 4. Create Kuadrant CR in kuadrant-system
oc create namespace kuadrant-system
oc apply -f - <<EOF
apiVersion: kuadrant.io/v1beta1
kind: Kuadrant
metadata:
  name: kuadrant
  namespace: kuadrant-system
spec: {}
EOF

# Wait for Authorino:
oc get pods -n kuadrant-system -w
```

### 5. Inference Gateways + TLS

Two gateways are created: one for MaaS API traffic and one for direct model inference. Both need a TLS secret and passthrough Routes. Unchanged from 3.4.

| Gateway                  | Hostname                           | Purpose                                     |
| ------------------------ | ----------------------------------- | -------------------------------------------- |
| `maas-default-gateway`   | `maas.apps.<cluster>`              | MaaS API + model endpoints (Authorino auth) |
| `openshift-ai-inference` | `inference-gateway.apps.<cluster>` | Direct llm-d model access                   |

> **Warning — `default-gateway-tls` Secret:**
> The gateways reference a TLS secret that is **NOT auto-created** by any operator. Without it, Envoy never starts port 443 and all traffic returns 503. The toolkit uses cert-manager to issue a proper wildcard Certificate CR (auto-renewed). Fallback: copy an existing wildcard cert or use router-ca.

> **Note — Passthrough Routes:**
> `*.apps.<cluster>` DNS points to the default OpenShift Router, not to the gateway LoadBalancers. Passthrough Routes bridge the two.

See [RHOAI-34-MANUAL-INSTALLATION-GUIDE.md](../rhoai-3.4/RHOAI-34-MANUAL-INSTALLATION-GUIDE.md) for the full manual YAML for GatewayClass, Gateway, Certificate, and passthrough Route creation — these steps and manifests are unchanged in 3.5.

### 6. User Workload Monitoring

- Enables Prometheus user workload monitoring (required for MaaS Tenant to report Ready, and now also required for the llm-d observability dashboards that are installed by default in 3.5)

### 7. RHOAI Operator

- Interactive channel selection (or `--channel stable-3.5`)
- Creates operator subscription
- The default channel suggestion now prefers `stable-3.5` over `fast-3.x`, since `fast-3.x` has been observed lagging behind `stable-3.x` on some clusters

**Manual Commands**

```bash
# Install RHOAI operator (channel: stable-3.5)
export RHOAI_CHANNEL=stable-3.5
envsubst '${RHOAI_CHANNEL}' < lib/manifests/rhoai/rhoai-subscription.yaml | oc apply -f -

# Wait for CSV
oc get csv -n redhat-ods-operator -w
```

### 8. DataScienceCluster

Applies [`datasciencecluster-v3-35.yaml`](../../../lib/manifests/rhoai/datasciencecluster-v3-35.yaml) (API v2) with all components enabled.

| Component                | State     | Notes                                                          |
| ------------------------- | --------- | --------------------------------------------------------------- |
| `dashboard`              | Managed   | Web interface                                                  |
| `workbenches`            | Managed   | Jupyter/IDE, Red Hat Python index (2025.2 images retained)     |
| `aipipelines`            | Managed   | Kubeflow Pipelines; MLflow tracking now embedded automatically |
| `kserve`                 | Managed   | Model serving (RawDeployment + Headed); canary rollout support |
| `kserve.nim`             | Managed   | NVIDIA NIM support                                             |
| `kserve.modelsAsService` | Managed   | MaaS (GA since 3.4; external OIDC auth now GA in 3.5)          |
| `kueue`                  | Unmanaged | Using standalone Kueue Operator                                |
| `ray`                    | Managed   | Distributed computing; KubeRay upgraded to 1.6.x               |
| `trainer`                | Removed   | Enable if JobSet operator installed                            |
| `trainingoperator`       | Removed   | Deprecated, use `trainer`                                      |
| `modelregistry`          | Managed   | OCI storage, PostgreSQL backend                                |
| `trustyai`               | Managed   | NeMo Guardrails, EvalHub (now GA), Automated Red Teaming (GA)  |
| `feastoperator`          | Managed   | Feature Store (TP); SparkApplication batch engine (new)        |
| `llamastackoperator`     | Managed   | OGX (formerly Llama Stack); Responses API now GA               |
| `mlflowoperator`         | Managed   | MLflow (managed DSC component); now integrated across pipelines/trainer/workbenches |

**Manual Commands**

```bash
# Create DataScienceCluster (API v2)
oc apply -f lib/manifests/rhoai/datasciencecluster-v3-35.yaml
# Key: spec.components.kserve.modelsAsService.managementState: Managed
```

### 9. MaaS TLS Configuration (Authorino)

RHOAI 3.5 continues to use OpenShift service-ca for Authorino TLS (not cert-manager) — unchanged from 3.4. This configures internal auth filter TLS between the gateway Envoy and Authorino.

| Step                       | What It Does                                                   |
| --------------------------- | ---------------------------------------------------------------- |
| Annotate Authorino service | Triggers service-ca to generate `authorino-server-cert` secret |
| Patch Authorino CR         | Enables TLS listener with the generated cert                   |
| Set env vars on Authorino  | `SSL_CERT_FILE` + `REQUESTS_CA_BUNDLE` for CA validation        |
| Annotate gateway           | `authorino-tls-bootstrap=true` creates EnvoyFilter for TLS      |

**Manual Commands**

```bash
# 1. Annotate Authorino service for service-ca cert
oc annotate service authorino-authorino-authorization \
  -n kuadrant-system \
  service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert \
  --overwrite

# 2. Patch Authorino CR for TLS listener
oc patch authorino authorino -n kuadrant-system --type=merge --patch '{
  "spec": {
    "listener": {
      "tls": {
        "enabled": true,
        "certSecretRef": {"name": "authorino-server-cert"}
      }
    }
  }
}'

# 3. Set TLS env vars
oc -n kuadrant-system set env deployment/authorino \
  SSL_CERT_FILE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt \
  REQUESTS_CA_BUNDLE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt

# 4. Annotate gateway
oc annotate gateway maas-default-gateway -n openshift-ingress \
  security.opendatahub.io/authorino-tls-bootstrap="true" --overwrite
```

### 10. MaaS PostgreSQL Setup

MaaS requires PostgreSQL 14+ for API key validation — unchanged from 3.4. The script handles this automatically:

- **No `--postgres-connection` flag**: Deploys a POC PostgreSQL (5Gi PVC, not production-grade) in `redhat-ods-applications`
- **With `--postgres-connection`**: Creates the secret from your external database URL
- **With `--skip-maas-db`**: Skips entirely (you manage the secret yourself)

The secret format is a single connection URL:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: maas-db-config
  namespace: redhat-ods-applications
type: Opaque
stringData:
  DB_CONNECTION_URL: "postgresql://user:pass@host:5432/db?sslmode=require"
```

For production, use AWS RDS, Crunchy Postgres Operator, or Azure Database for PostgreSQL.

### 11. Dashboard Configuration

Several feature flags in `OdhDashboardConfig` control MaaS and other 3.5 features in the UI.

| Flag                    | Value   | What It Enables                          |
| ------------------------ | ------- | ------------------------------------------ |
| `modelAsService`        | `true`  | MaaS section in Gen AI studio             |
| `vLLMDeploymentOnMaaS`  | `true`  | Non-legacy deployment + Publish as MaaS   |
| `genAiStudio`           | `true`  | Gen AI studio top-level menu, incl. the unified MaaS governance page |
| `disableModelCatalog`   | `false` | Model Catalog page                        |
| `externalModels`        | `true`  | **New in 3.5 (TP)**: External model endpoints view in AI hub |
| `toolCalling`           | `true`  | **New in 3.5**: Validated tool-calling config on Model Catalog cards |

> **Warning —** `vLLMDeploymentOnMaaS`**:** This flag is critical. Without it, the dashboard only shows the legacy InferenceService path, and there is no option to publish models to MaaS.

> **Breaking change confirmed on a live RHOAI 3.5.0 GA cluster (not called out in public release notes):**
> `maasAuthPolicies` is now **rejected** by `OdhDashboardConfig`'s CEL validation with
> `DEPRECATED: spec.dashboardConfig.maasAuthPolicies must be removed or left unchanged`.
> Attempting to set it on a fresh 3.5 install fails the entire patch. **Do not include this
> field** when patching `OdhDashboardConfig` on RHOAI 3.5 — it was valid in 3.4 but is no
> longer accepted. The Subscriptions + Authorization Policies UI it used to gate is now
> reached via the unified "MaaS governance" page, gated by `genAiStudio`/`modelAsService` alone.

**Manual Command**

```bash
oc patch odhdashboardconfig odh-dashboard-config \
  -n redhat-ods-applications --type=merge -p '{
  "spec": {
    "dashboardConfig": {
      "genAiStudio": true,
      "modelAsService": true,
      "vLLMDeploymentOnMaaS": true,
      "disableModelRegistry": false,
      "disableModelCatalog": false,
      "disableKServeMetrics": false,
      "disableLMEval": false,
      "externalModels": true,
      "toolCalling": true
    }
  }
}'
```

### 12. Deploy a Model + Publish to MaaS, 13. Subscriptions/Auth Policies/API Keys, 14. Verification

These workflows are unchanged from 3.4. See [RHOAI-34-INSTALLATION.md](../rhoai-3.4/RHOAI-34-INSTALLATION.md) sections 12–14 for full manual command examples (model deployment via `LLMInferenceService`, `MaaSModelRef`, `MaaSSubscription`, `MaaSAuthPolicy`, and verification commands) — only the dashboard governance page location changed (unified "MaaS governance" page instead of separate Subscriptions/Authorization Policies pages).

**Toolkit Automation**

```bash
# Interactive wizard — prompts for MaaS mode + publish on RHOAI 3.4+/3.5
source lib/functions/model-deployment.sh
deploy_model_interactive

# Or use serve-model.sh with MAAS_PUBLISH flag
MAAS_PUBLISH=true ./scripts/serve-model.sh oci qwen3-4b \
  oci://quay.io/redhat-ai-services/modelcar-catalog:qwen3-4b
```

---

## User Management

The toolkit can create demo users with htpasswd authentication and organize them into groups for MaaS access. Unchanged from 3.4.

### During Installation

```bash
./scripts/install-rhoai-35.sh --setup-users --num-users 10 --user-password demo123
```

### Standalone (after installation)

```bash
# Basic: 5 users, default groups
./scripts/setup-users.sh

# Custom: 10 users, custom groups
./scripts/setup-users.sh --num-users 10 --admin-group team-leads --user-group developers
```

---

## Troubleshooting

| Problem                      | Root Cause                           | Fix                                                      |
| ----------------------------- | ------------------------------------- | ----------------------------------------------------------- |
| Gateway returns 503          | `default-gateway-tls` secret missing | Create TLS secret via cert-manager or copy wildcard cert |
| API Keys page: Error loading | maas-ui can't reach gateway URL      | Create passthrough Route from Router to gateway          |
| No "Publish as MaaS" option  | `vLLMDeploymentOnMaaS` not set       | Patch `OdhDashboardConfig`                               |
| No subscriptions for API key | User not in owner group              | Add user to group or patch `spec.owner.users`             |
| RHCL operator stuck          | OLM set InstallPlan to Manual        | Auto-approve pending InstallPlans                         |
| MLflow unavailable           | No MLflow CR created                 | Create MLflow CR with sqlite + PVC                        |
| `stable-3.x` channel picks wrong installer | Toolkit menu doesn't recognize the channel | Fixed — `lib/menus/install.sh` now routes `stable-3.x`/`stable-3.5`/`eus-3.5` to `install-rhoai-35.sh` |
| llm-d flow control resources fail after upgrade from 3.4 TP | API group/metrics prefix renamed | Update `InferenceObjective`/`EndpointPickerConfig` to `llm-d.ai`; update dashboards/alerts to `llm_d_epp_` prefix |
| `oc patch odhdashboardconfig` fails with `no such key: maasAuthPolicies` | `maasAuthPolicies` field removed/locked by 3.5's CEL validation (confirmed on live cluster) | Omit `maasAuthPolicies` entirely from the patch — `install-rhoai-35.sh` already does this |

For the full gateway-TLS and dashboard-flag troubleshooting walkthroughs (unchanged from 3.4), see [RHOAI-34-INSTALLATION.md](../rhoai-3.4/RHOAI-34-INSTALLATION.md#troubleshooting).

---

## Changes from 3.4

| Area              | 3.4                                              | 3.5                                                                                    |
| ------------------ | -------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| MaaS external OIDC | Technology Preview                                 | **GA**                                                                                    |
| MaaS routing       | Path-based only                                    | Path-based **+ OpenAI-compatible body-based routing**                                    |
| MaaS governance UI | Separate Subscriptions / Authorization Policies    | **Unified MaaS governance page**                                                          |
| MaaS multi-tenancy | N/A                                                 | Technology Preview (per-tenant gateway + identity isolation)                              |
| EvalHub            | Technology Preview                                 | **GA** (SDK, CLI, MCP server, per-tenant deployment)                                      |
| Automated Red Teaming (Garak) | N/A (or early TP)                       | **GA**                                                                                     |
| llm-d flow control | Technology Preview                                 | **GA** — breaking API group/metrics-prefix rename (see What's New doc)                    |
| OGX (Llama Stack)  | "Llama Stack" naming, Responses API TP             | Renamed to **OGX**; Responses API **GA**; multi-tenancy support                          |
| Kueue              | No self-managed queue flag                         | Optional flag to disable automatic default queue creation; scheduling visibility in UI    |
| KServe             | No canary support; no OAuth proxy resource config  | **Canary rollout** for RawDeployment; `kserve.oauthProxy.resources` configurable          |
| Dashboard flags    | `modelAsService`, `maasAuthPolicies`, `vLLMDeploymentOnMaaS` (TP), `observabilityDashboard` (TP) | `maasAuthPolicies` **removed/rejected** (confirmed on live cluster); + `externalModels` (TP), `toolCalling` |
| Install script     | `install-rhoai-34.sh`                              | `install-rhoai-35.sh`                                                                      |
| DSC manifest        | `datasciencecluster-v3-34.yaml`                    | `datasciencecluster-v3-35.yaml` (API v2, unchanged)                                        |
| Channel             | `stable-3.4` (default recommendation)              | `stable-3.5` (default recommendation); `stable-3.x` now also resolves to 3.5.0             |
