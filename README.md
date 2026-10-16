# sample-k8s-argocd-bootstrap

Manifests and scripts for installing and managing ArgoCD on the Lima vanilla Kubernetes cluster.

## Related repositories

This repo is part of a three-repo GitOps setup:

| Repository | Purpose | Access |
|---|---|---|
| [sample-k8s-argocd-bootstrap](https://github.com/gek0/sample-k8s-argocd-bootstrap) (this repo) | Installs ArgoCD; owns platform-level config (projects, repository credentials, RBAC) | DevOps/operators only |
| [sample-k8s-gitops](https://github.com/gek0/sample-k8s-gitops) | ArgoCD Application and ApplicationSet definitions; per-environment app manifests | Developers |
| [sample-k8s-app](https://github.com/gek0/sample-k8s-app) | Kubernetes manifests for the nginx sample application (Deployment, Service, HPA) | Developers |

### How they work together

```
sample-k8s-argocd-bootstrap
  └── installs ArgoCD + applies argocd/ (projects, repo credentials)
        │
        ▼
    ArgoCD running in-cluster
        │
        ├── Application: github-personal-hpa-test  ──watches──▶  sample-k8s-app
        │     deploys nginx Deployment, Service, HPA
        │
        └── ApplicationSet: s3-buckets  ──watches──▶  sample-k8s-gitops/apps/{dev,prod}
              generates one Application per env, deploys Crossplane S3 Buckets
```

**Bootstrap repo** owns the trust boundary — it defines which repos ArgoCD is allowed to sync from and what each project can deploy. Changes here require operator review.

**Gitops repo** is where application teams manage what gets deployed and to which environment. ArgoCD reconciles it continuously.

**App repo** holds the actual workload manifests. ArgoCD watches it and applies changes automatically on every push.

## Prerequisites

- Running Lima k8s cluster (see [lima-vanilla-k8s](https://github.com/gek0/lima-vanilla-k8s))
- Istio installed and the `primary-gateway` present in `istio-system`
- MetalLB configured (ArgoCD is assigned `192.168.104.52`)
- `kubectl` context pointed at the cluster

## Installation

### Option A — manifest-installer script (recommended)

From the `lima-vanilla-k8s` repo root:

```bash
bash k8s/scripts/manifest-installer.sh
# select: argocd
```

The script applies `install/` manifests in the correct order, waits for ArgoCD to be ready, then runs `patch-service.sh`.

### Option B — manual

Apply in order:

```bash
# 1. Create the argocd namespace (Istio sidecar injection enabled)
kubectl apply -f install/namespace.yaml

# 2. Install ArgoCD
kubectl apply -f install/install.yaml

# 3. Apply cluster-local config (runs argocd-server in insecure mode — TLS handled by Istio)
kubectl apply -f install/argocd-server-cm.yaml

# 4. Apply Istio networking rules
kubectl apply -f install/istio-destinationrule.yaml
kubectl apply -f install/istio-virtualservice.yaml

# 5. Patch argocd-server service to LoadBalancer and fetch the initial admin password
bash install/patch-service.sh
```

## ArgoCD resources

The `core/` directory holds DevOps-managed ArgoCD configuration — things that operators own and developers should not modify directly:

- **projects** — `AppProject` definitions (RBAC boundaries, allowed repos and destinations)
- Any other cluster-scoped ArgoCD components (RBAC policies, notifications, etc.)

Apply on initial setup after installation, and re-apply whenever this directory changes:

```bash
kubectl apply -R -f core/
```

## Accessing ArgoCD

| Method | URL |
|---|---|
| In-cluster (MetalLB) | http://192.168.104.52 |
| Virtual host (Istio) | http://argocd.local.io |
| Mac port-forward | http://localhost:8080 (via `port-forward.sh`) |

Username: `admin`  
Password: printed by `patch-service.sh`, or retrieve manually:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

## Updating ArgoCD

Replace `install/install.yaml` with the new upstream release manifest and re-apply:

```bash
# Download the new version
curl -sL https://raw.githubusercontent.com/argoproj/argo-cd/v<VERSION>/manifests/install.yaml \
  -o install/install.yaml

kubectl apply -f install/install.yaml
```

## File reference

| File | Purpose |
|---|---|
| `install/namespace.yaml` | `argocd` namespace with `istio-injection: enabled` |
| `install/install.yaml` | Upstream ArgoCD install manifest |
| `install/argocd-server-cm.yaml` | Sets `server.insecure: true` — required for this dev setup and Istio |
| `install/istio-destinationrule.yaml` | Disables mTLS between Istio sidecar and argocd-server (plain HTTP inside mesh) |
| `install/istio-virtualservice.yaml` | Routes `argocd.local.io` → `argocd-server:80` via `istio-system/primary-gateway` |
| `install/patch-service.sh` | Patches service to LoadBalancer, assigns MetalLB IP, prints admin password |
| `install/wait-for` | Resource list used by the manifest-installer to wait for ArgoCD readiness before patching |
| `core/` | DevOps-managed ArgoCD resources (projects, repositories, etc.) — apply with `kubectl apply -R -f core/` |
