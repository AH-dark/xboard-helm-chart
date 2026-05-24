# xboard Helm Chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/xboard)](https://artifacthub.io/packages/search?repo=xboard)
[![Lint Charts](https://img.shields.io/github/actions/workflow/status/AH-dark/xboard-helm-chart/lint.yml?branch=main&label=lint&logo=github)](https://github.com/AH-dark/xboard-helm-chart/actions/workflows/lint.yml)
[![Release Charts](https://img.shields.io/github/actions/workflow/status/AH-dark/xboard-helm-chart/release.yml?branch=main&label=release&logo=github)](https://github.com/AH-dark/xboard-helm-chart/actions/workflows/release.yml)
[![License](https://img.shields.io/github/license/AH-dark/xboard-helm-chart?label=license)](LICENSE)

Helm chart for deploying the [XBoard](https://github.com/cedar2025/xboard) panel (web + horizon + ws-server) on Kubernetes.

**Chart**: `0.1.1` · **App**: `latest` · **Kubernetes**: `≥ 1.29` · **Helm**: `≥ 3.14`

## Overview

This chart deploys three components of XBoard:

| Component     | Description                    | Resources                                     |
| ------------- | ------------------------------ | --------------------------------------------- |
| **web**       | HTTP server (Laravel app)      | Deployment + Service + HTTPRoutes + HPA + PDB |
| **horizon**   | Queue worker (Laravel Horizon) | Deployment + HPA + PDB                        |
| **ws-server** | WebSocket server               | Deployment + Service + HTTPRoute + HPA + PDB  |

**Out of scope** (manage separately): PostgreSQL database (CNPG), Redis (Bitnami chart), TLS certificate (cert-manager), and ArgoCD Application resources.

---

## Prerequisites

- Kubernetes >= 1.29
- Helm >= 3.14
- [Gateway API v1 CRDs](https://gateway-api.sigs.k8s.io/guides/) installed in cluster
- CNPG Cluster `xboard-app-db` deployed and ready (provides `xboard-app-db-rw` service)
- Bitnami Redis release `redis` deployed (provides `redis-master` service)
- Stakater Reloader operator (optional, required when `reloader.enabled=true`)

---

## Installation

### From Helm repository

```bash
helm repo add xboard https://ah-dark.github.io/xboard-helm-chart
helm repo update
helm install xboard xboard/xboard \
  --namespace xboard \
  --create-namespace
```

### From source

```bash
git clone https://github.com/AH-dark/xboard-helm-chart.git
helm install xboard ./xboard-helm-chart/charts/xboard \
  --namespace xboard \
  --create-namespace
```

### APP_KEY handling

The chart auto-generates `APP_KEY` when it is left empty and no `config.existingSecret` is set. On `helm upgrade` the existing in-cluster value is reused via `helm lookup`, so pods are not invalidated.

For reproducible output (e.g. GitOps with `helm template`, dry-runs, or fully deterministic installs), set the key explicitly:

```bash
helm install xboard xboard/xboard \
  --namespace xboard \
  --create-namespace \
  --set config.values.APP_KEY="base64:$(openssl rand -base64 32)"
```

---

## Values Reference

### Image

| Key                 | Default                                                 | Description                |
| ------------------- | ------------------------------------------------------- | -------------------------- |
| `image.repository`  | `ghcr.io/cedar2025/xboard`                              | Container image repository |
| `image.tag`         | `""` (uses appVersion: latest)                          | Image tag override         |
| `image.pullPolicy`  | `""` (auto: Always for latest/empty, else IfNotPresent) | Pull policy override       |
| `image.pullSecrets` | `[]`                                                    | Image pull secrets         |

### Config (Application Environment)

| Key                        | Default                     | Description                                                                                                                                   |
| -------------------------- | --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `config.existingSecret`    | `""`                        | Reference an existing Secret (bypasses config.values and APP_KEY generation)                                                                  |
| `config.values.APP_KEY`    | `""`                        | Laravel encryption key. Empty = auto-generated at render time (reused via `helm lookup` on upgrade). Set explicitly for reproducible renders. |
| `config.values.APP_URL`    | `https://panel.example.com` | Application URL                                                                                                                               |
| `config.values.DB_HOST`    | `xboard-app-db-rw`          | PostgreSQL hostname (CNPG read-write service)                                                                                                 |
| `config.values.REDIS_HOST` | `redis-master`              | Redis hostname                                                                                                                                |
| `config.extraValues`       | `{}`                        | Additional env vars to merge into the Secret                                                                                                  |

### Per-Component Scaling (web / horizon / ws)

| Key                       | Default | Description            |
| ------------------------- | ------- | ---------------------- |
| `web.hpa.enabled`         | `true`  | Enable HPA for web     |
| `web.hpa.minReplicas`     | `2`     | Minimum replicas       |
| `web.hpa.maxReplicas`     | `8`     | Maximum replicas       |
| `horizon.hpa.minReplicas` | `2`     | Horizon min replicas   |
| `horizon.hpa.maxReplicas` | `4`     | Horizon max replicas   |
| `ws.hpa.minReplicas`      | `2`     | WS-server min replicas |
| `ws.hpa.maxReplicas`      | `4`     | WS-server max replicas |
| `web.pdb.enabled`         | `true`  | Enable PDB for web     |
| `web.pdb.minAvailable`    | `"25%"` | Minimum available pods |

### Ingress (Gateway API)

This chart only renders HTTPRoutes; the referenced Gateway must be provisioned out of band (for example via `xboard/cert/gateway.yaml` or a shared cluster-level gateway).

| Key                           | Default                                        | Description                             |
| ----------------------------- | ---------------------------------------------- | --------------------------------------- |
| `ingress.hostname`            | `panel.example.com`                            | Public hostname                         |
| `ingress.hsts.enabled`        | `true`                                         | Add HSTS response header                |
| `ingress.redirectHttpToHttps` | `true`                                         | Render HTTP to HTTPS redirect HTTPRoute |
| `ingress.parentRefs.https`    | `[{name: xboard-gateway, sectionName: https}]` | HTTPS listener parentRef                |
| `ingress.parentRefs.http`     | `[{name: xboard-gateway, sectionName: http}]`  | HTTP listener parentRef                 |

---

## Secret Dual-Mode

### Mode 1: Inline values (development / simple setups)

The chart renders a Secret from `config.values`. `APP_KEY` is auto-generated when empty; pass it explicitly only when you need a stable, externally-known value:

```bash
helm install xboard xboard/xboard \
  --namespace xboard \
  --set config.values.APP_KEY="base64:$(openssl rand -base64 32)" \
  --set config.values.DB_PASSWORD="my-db-password" \
  --set config.values.REDIS_PASSWORD="my-redis-password"
```

### Mode 2: External Secret (production / GitOps)

Pre-create the Secret externally, then reference it:

```bash
# Create secret beforehand (e.g. via Sealed Secrets, External Secrets, etc.)
kubectl create secret generic my-xboard-config \
  --namespace xboard \
  --from-env-file=config.env

# Install chart pointing to existing secret
helm install xboard xboard/xboard \
  --namespace xboard \
  --set config.existingSecret=my-xboard-config
```

When `config.existingSecret` is set, `config.values` is **completely ignored** and no Secret is rendered by this chart.

---

## Bring Your Own Gateway

This chart does not render a `Gateway` resource. It assumes an external Gateway named `xboard-gateway` already exists in the namespace (e.g. deployed from `xboard/cert/gateway.yaml`).

To point HTTPRoutes at a different Gateway (e.g. shared cluster-level gateway):

```yaml
# values-override.yaml
ingress:
  parentRefs:
    https:
      - name: shared-gateway
        namespace: gateway-system
        sectionName: https
    http:
      - name: shared-gateway
        namespace: gateway-system
        sectionName: http
```

---

## Upgrade & Uninstall

### Upgrade

```bash
helm upgrade xboard xboard/xboard \
  --namespace xboard
```

The auto-generated `APP_KEY` is preserved across upgrades via `helm lookup`. To rotate it, pass `--set config.values.APP_KEY="base64:$(openssl rand -base64 32)"` (note: pods using the previous key will need to re-encrypt any APP_KEY-encrypted data).

> **Important**: Selector labels are immutable. If you need to change selector labels, you must uninstall and reinstall (with downtime).

### Uninstall

```bash
helm uninstall xboard --namespace xboard
```

Note: PVCs (if any) and Secrets created outside this chart are NOT deleted by `helm uninstall`.

---

## License

This chart is distributed under the [GNU Affero General Public License v3.0 or later](LICENSE) (`AGPL-3.0-or-later`).
