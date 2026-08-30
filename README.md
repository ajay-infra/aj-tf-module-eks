# aj-tf-module-eks

Terraform module for AWS EKS — production-grade, blue/green aware, with dynamic node groups, EKS Pod Identity, and FinOps controls for dev through regulated-prod environments.

---

## Version Requirements

| Tool / Provider | Pinned version | Notes |
|---|---|---|
| Terraform | `= 1.10.5` | Exact pin — upgrade deliberately after testing |
| AWS Provider (`hashicorp/aws`) | `= 5.100.0` | Exact pin — avoid surprise drift |
| Kubernetes | `1.35` (default) | See support lifecycle below |

> Versions are **exact pins**, not ranges. This prevents unintended provider upgrades in CI or shared environments. When you want to upgrade, bump the version explicitly, run `terraform init -upgrade`, test, then commit.

### EKS Kubernetes support lifecycle

EKS provides **14 months of standard support** per minor version from its release date. After that, **extended support automatically activates** at an extra **$0.60/cluster/hour (~$438/month per cluster)** — billed even if you don't opt in.

| Version | Released | EKS Std support ends | Action |
|---|---|---|---|
| 1.32 | Dec 2024 | ~Feb 2026 | Migrate off |
| 1.33 | Apr 2025 | ~Jun 2026 | Migrate off soon |
| 1.34 | Aug 2025 | ~Oct 2026 | Active |
| **1.35** | **Dec 2025** | **~Feb 2027** | **Current default — use this** |

Always keep `k8s_version` within its standard support window to avoid the extended support charge.

---

## Deployment Modes

| Mode | Clusters | When to use |
|---|---|---|
| `standalone` | 1 | Dev, staging, patch upgrades (1.30.x → 1.30.y) |
| `blue_green` | 1 per color (blue + green) | Zero-downtime minor/major K8s version upgrades |

**Upgrade rule:**
- Patch upgrade (1.30.x → 1.30.y) → in-place OK, use `standalone`
- Minor upgrade (1.35 → 1.36) → blue/green **mandatory**
- Major add-on changes → blue/green **mandatory**

---

## Module Structure

```
aj-tf-module-eks/
├── main.tf              # orchestrates all submodules via for_each
├── variables.tf         # all inputs (core, networking, az_count, node_groups, pod_identity)
├── outputs.tf           # cluster, node group map, AZ, pod identity outputs
├── locals.tf            # name_prefix, active subnet slicing, full_tags
├── providers.tf         # AWS provider >= 5.0, default_tags
├── example.tfvars       # ready-to-run dev example
└── modules/
    ├── eks-cluster/     # control plane + SGs + managed add-ons
    ├── node-group/      # reusable node group — called via for_each
    └── pod-identity/    # Pod Identity IAM role + association (replaces IRSA)
```

---

## Quick Start

### Standalone — dev / staging

```hcl
module "eks" {
  source = "github.com/ajay-infra/aj-tf-module-eks"

  cluster_name        = "ai-search-dev"
  environment         = "dev"
  k8s_version         = "1.35"
  eks_deployment_mode = "standalone"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids   # ordered by AZ
  public_subnet_ids  = module.vpc.public_subnet_ids

  az_count          = 2                  # 2 AZs for dev — lower cost
  cluster_log_types = ["api", "audit"]   # minimal logging for dev

  node_groups = {
    frontend = {
      instance_types = ["m6i.xlarge"]
      desired_size   = 1
      min_size       = 1
      max_size       = 3
      capacity_type  = "SPOT"           # SPOT for dev cost savings
    }
    backend = {
      instance_types = ["m6i.2xlarge"]
      desired_size   = 1
      min_size       = 1
      max_size       = 3
      capacity_type  = "SPOT"
    }
  }
}
```

### Blue/Green — production (Day 0: provision blue)

```hcl
module "eks_blue" {
  source = "github.com/ajay-infra/aj-tf-module-eks"

  cluster_name        = "ai-search-prod-blue"
  environment         = "prod"
  k8s_version         = "1.35"
  eks_deployment_mode = "blue_green"
  color               = "blue"

  vpc_id             = module.vpc.blue_vpc_id
  private_subnet_ids = module.vpc.blue_private_subnet_ids
  public_subnet_ids  = module.vpc.blue_public_subnet_ids

  az_count = 3   # 3 AZs standard HA for prod

  node_groups = {
    frontend = {
      instance_types = ["m6i.xlarge"]
      desired_size   = 3
      min_size       = 2
      max_size       = 6
      labels         = { workload = "frontend" }
    }
    backend = {
      instance_types = ["m6i.2xlarge"]
      desired_size   = 2
      min_size       = 1
      max_size       = 5
      labels         = { workload = "backend", role = "rag" }
    }
    gpu = {
      instance_types = ["g4dn.xlarge"]
      desired_size   = 2
      min_size       = 0
      max_size       = 4
      ami_type       = "AL2_x86_64_GPU"
      disk_size_gb   = 100
      labels         = { workload = "gpu-inference", "nvidia.com/gpu.present" = "true" }
      taints         = [{ key = "nvidia.com/gpu", value = "true", effect = "NO_SCHEDULE" }]
    }
  }

  pod_identity_associations = {
    aws-lbc = {
      namespace            = "kube-system"
      service_account_name = "aws-load-balancer-controller"
      policy_arns          = [aws_iam_policy.lbc.arn]
    }
    karpenter = {
      namespace            = "kube-system"
      service_account_name = "karpenter"
      policy_arns          = [aws_iam_policy.karpenter.arn]
    }
    external-secrets = {
      namespace            = "external-secrets"
      service_account_name = "external-secrets"
      policy_arns          = [aws_iam_policy.external_secrets.arn]
    }
  }
}
```

### Blue/Green — K8s upgrade day (provision green)

```hcl
module "eks_green" {
  source = "github.com/ajay-infra/aj-tf-module-eks"

  cluster_name        = "ai-search-prod-green"
  environment         = "prod"
  k8s_version         = "1.36"           # ← next version when upgrading from 1.35
  eks_deployment_mode = "blue_green"
  color               = "green"

  # Same node_groups / pod_identity_associations as blue
  # Switch Route53 weighted record once green is validated
  # Destroy blue after traffic is fully migrated
}
```

---

## Environment Profiles

Use these as a reference when deciding `az_count`, `capacity_type`, `cluster_log_types`, and node sizing.

| Setting | Dev | Staging | Production | Regulated Prod |
|---|---|---|---|---|
| `az_count` | `2` | `2` | `3` | `4` |
| `capacity_type` | `SPOT` | `SPOT` | `ON_DEMAND` | `ON_DEMAND` |
| `cluster_log_types` | `[]` or `["api","audit"]` | `["api","audit"]` | all 5 | all 5 |
| `desired_size` per group | `1` | `1–2` | `2–3` | `3+` |
| `eks_deployment_mode` | `standalone` | `standalone` | `blue_green` | `blue_green` |
| GPU node group | no | no | optional | optional |
| SLA target | none | internal | 99.9% | 99.99% |

---

## AZ Count — FinOps Guide

Pass **all** subnets from `aj-tf-module-vpc` (ordered by AZ). The module slices to `az_count` automatically.

```hcl
az_count = 2   # uses first 2 subnets from private_subnet_ids / public_subnet_ids
```

| `az_count` | Use case | Trade-off |
|---|---|---|
| `2` | Dev / staging | Lower cross-AZ data transfer costs; single AZ failure impacts 50% of nodes |
| `3` | Standard prod HA | Balanced cost vs resilience; single AZ failure impacts ~33% |
| `4` | Regulated / financial | Highest resilience; highest cross-AZ transfer cost |

> Subnets **must be ordered by AZ** in the list (standard output from `aj-tf-module-vpc`).

---

## CNI Options

Set `cni = "vpc-cni"` (default) or `cni = "cilium"` in your tfvars.

### Comparison

| | AWS VPC CNI | AWS VPC CNI + Prefix Delegation | Cilium (recommended) |
|---|---|---|---|
| **Pod IPs come from** | VPC subnet CIDR | VPC subnet CIDR | `pod_cidr` (separate range) |
| **IP exhaustion risk** | High — 1 VPC IP per pod | Medium — 16 IPs per ENI slot | None — VPC IPs only on nodes |
| **Max pods per node** | Limited by ENI slots × IPs per ENI | ~110–250 (prefix size) | Thousands (only limited by CPU/memory) |
| **kube-proxy** | Required | Required | Replaced by eBPF (faster) |
| **Network policy** | Requires Calico/separate tool | Requires Calico/separate tool | Built-in (L3/L4/L7 + DNS-based) |
| **Observability** | VPC Flow Logs | VPC Flow Logs | Hubble (per-flow, pod-level, UI) |
| **Cross-AZ performance** | Native VPC routing | Native VPC routing | VXLAN overlay (~5–10% overhead) |
| **Complexity** | Low | Low-medium | Medium |
| **AWS managed** | Yes | Yes | No (Helm-managed) |
| **`cni` value** | `"vpc-cni"` | `"vpc-cni"` + manual config | `"cilium"` |

### What changes when `cni = "cilium"`

This module automatically:
- Strips `vpc-cni` and `kube-proxy` from the managed addons (Cilium replaces both via eBPF)
- Keeps `coredns`, `pod-identity-agent`, and `aws-ebs-csi-driver` unchanged
- Outputs `cilium_helm_values` with the exact Helm values to pass in your aj-cluster-baseline layer

Cilium itself is **installed via Helm in your aj-cluster-baseline layer** (not in this module) to keep a clean separation between cluster provisioning and workload installation.

### Installing Cilium after cluster apply

```bash
# Add the Cilium Helm repo
helm repo add cilium https://helm.cilium.io/
helm repo update

# Install using values from this module's output
helm install cilium cilium/cilium \
  --version $(terraform output -raw cilium_version) \
  --namespace kube-system \
  $(terraform output -json cilium_helm_values | \
    jq -r 'to_entries[] | "--set \(.key)=\(.value)"' | tr '\n' ' ')
```

Or pass values directly:

```bash
helm install cilium cilium/cilium \
  --version 1.17.0 \
  --namespace kube-system \
  --set routingMode=tunnel \
  --set tunnelProtocol=vxlan \
  --set ipam.mode=cluster-pool \
  --set "ipam.operator.clusterPoolIPv4PodCIDRList[0]=100.64.0.0/10" \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=<cluster_endpoint> \
  --set k8sServicePort=443 \
  --set eni.enabled=false \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true
```

> **Note:** Install Cilium before scaling node groups or nodes will remain `NotReady` until the CNI DaemonSet is running.

---

## Inputs

### Core

| Variable | Required | Default | Description |
|---|---|---|---|
| `cluster_name` | yes | — | EKS cluster name (e.g. `ai-search-prod-blue`) |
| `aws_region` | no | `us-east-1` | AWS region |
| `environment` | no | `dev` | Environment label (used in resource names + tags) |
| `k8s_version` | no | `1.35` | Kubernetes version |
| `eks_deployment_mode` | no | `blue_green` | `standalone` or `blue_green` |
| `color` | no | `blue` | `blue` or `green` — blue_green mode only |

### Networking

| Variable | Required | Description |
|---|---|---|
| `vpc_id` | yes | From vpc module |
| `private_subnet_ids` | yes | All private subnets ordered by AZ |
| `public_subnet_ids` | yes | All public subnets ordered by AZ |
| `az_count` | no (default `3`) | How many AZs to spread across — `2`, `3`, or `4` |
| `endpoint_public_access` | no (default `true`) | Enable public API server endpoint |
| `endpoint_private_access` | no (default `true`) | Enable private API server endpoint |
| `public_access_cidrs` | no (default `["0.0.0.0/0"]`) | CIDRs allowed to reach the public endpoint |

### CNI

| Variable | Default | Description |
|---|---|---|
| `cni` | `"vpc-cni"` | `"vpc-cni"` or `"cilium"` — see CNI Options section |
| `pod_cidr` | `"100.64.0.0/10"` | Pod IP pool for Cilium overlay. Must not overlap VPC or service CIDR. Ignored for vpc-cni. |
| `cilium_version` | `"1.17.0"` | Cilium Helm chart version. Ignored for vpc-cni. |

### Control Plane Logging

| Variable | Default | Description |
|---|---|---|
| `cluster_log_types` | all 5 types | Log types sent to CloudWatch. Set `[]` in dev to eliminate ingestion cost |

Available types: `api`, `audit`, `authenticator`, `controllerManager`, `scheduler`

### Node Groups

`node_groups` is a `map(object(...))` — the map key becomes the group name in resource names and K8s labels.

```hcl
node_groups = {
  <group-name> = {
    # Required
    instance_types = list(string)   # EC2 types — first available wins
    desired_size   = number         # initial count; Karpenter/HPA manage at runtime
    min_size       = number
    max_size       = number

    # Optional (all have defaults)
    capacity_type  = string         # "ON_DEMAND" (default) | "SPOT"
    disk_size_gb   = number         # default 50; use 100+ for LLM model weights
    ami_type       = string         # "AL2_x86_64" (default) | "AL2_x86_64_GPU" | "BOTTLEROCKET_x86_64"
    labels         = map(string)    # K8s node labels; merged with { node-group = <key> }
    taints         = list(object({  # K8s taints for workload isolation
      key    = string
      value  = optional(string)
      effect = string               # "NO_SCHEDULE" | "PREFER_NO_SCHEDULE" | "NO_EXECUTE"
    }))
  }
}
```

### Pod Identity Associations

`pod_identity_associations` is a `map(object(...))` — the map key becomes part of the IAM role name.

```hcl
pod_identity_associations = {
  <logical-name> = {
    namespace            = string          # K8s namespace of the service account
    service_account_name = string          # K8s service account name
    policy_arns          = list(string)    # optional — managed or customer policy ARNs
    inline_policy        = string          # optional — raw JSON inline policy
  }
}
```

Leave as `{}` until IAM policies are provisioned by `infra-platform`.

### Add-ons

| Variable | Default | Description |
|---|---|---|
| `addons` | `coredns`, `kube-proxy`, `vpc-cni`, `pod-identity-agent`, `aws-ebs-csi-driver` | Override versions or add/remove managed add-ons |

### Tags

| Variable | Default | Description |
|---|---|---|
| `team` | `infra-core` | Team tag |
| `cost_center` | `infra-2026-q1` | Cost center tag |
| `common_tags` | `Project`, `ManagedBy`, `Repository` | Common tags merged into all resources |
| `tags` | `{}` | Extra tags |

---

## Outputs

| Output | Type | Description |
|---|---|---|
| `cluster_name` | string | EKS cluster name |
| `cluster_arn` | string | EKS cluster ARN |
| `cluster_endpoint` | string | API server endpoint |
| `cluster_ca_data` | string (sensitive) | CA certificate — used in kubeconfig |
| `cluster_version` | string | Kubernetes version |
| `cluster_security_group_id` | string | Control plane SG ID |
| `node_security_group_id` | string | Shared node SG ID — use for additional rules (e.g. Aurora, Redis) |
| `oidc_issuer` | string | OIDC URL (reference only — Pod Identity is used, not IRSA) |
| `node_group_arns` | map(string) | `{ frontend = "arn:...", backend = "arn:..." }` |
| `node_role_arns` | list(string) | All node IAM role ARNs — for aws-auth ConfigMap |
| `active_az_count` | number | AZs the cluster is spread across |
| `active_private_subnets` | list(string) | Private subnets in use (sliced to az_count) |
| `cni` | string | CNI mode in use: `vpc-cni` or `cilium` |
| `cilium_helm_values` | map(string) | Helm values for Cilium installation — null when cni = vpc-cni |
| `eks_deployment_mode` | string | `standalone` or `blue_green` |
| `color` | string | `blue` or `green` — for Route53 DNS routing |

---

## Pod Identity vs IRSA

This module uses **EKS Pod Identity** exclusively — no OIDC provider is created.

| | IRSA | Pod Identity |
|---|---|---|
| Auth mechanism | OIDC provider + JWT | Pod Identity Agent DaemonSet |
| Cluster limit | 1 OIDC per cluster | No limit |
| Cross-cluster reuse | New trust policy per cluster | Same role, multiple associations |
| Setup complexity | Medium | Low |
| EKS version required | Any | 1.24+ |

Pod Identity is the current AWS recommendation for new clusters (GA since EKS 1.29).

---

## Cost Reference

### By environment tier (us-east-1, On-Demand unless noted)

| Tier | Config | Est. monthly |
|---|---|---|
| **Dev** | 2 AZs · 2× SPOT m6i.xlarge + 2× SPOT m6i.2xlarge · no GPU · minimal logs | **~$150–250** |
| **Staging** | 2 AZs · 2× SPOT m6i.xlarge + 2× SPOT m6i.2xlarge · no GPU | **~$250–400** |
| **Prod (no GPU)** | 3 AZs · 3× m6i.xlarge + 2× m6i.2xlarge · all logs | **~$1,088** |
| **Prod (with GPU)** | 3 AZs · above + 2× g4dn.xlarge | **~$1,848** |
| **Regulated Prod** | 4 AZs · scaled-up groups + full logging | **~$2,200+** |

### Per-resource breakdown (On-Demand, prod sizing)

| Resource | Monthly |
|---|---|
| EKS control plane | ~$73 |
| m6i.xlarge × 3 (frontend) | ~$435 |
| m6i.2xlarge × 2 (backend) | ~$580 |
| g4dn.xlarge × 2 (GPU, if enabled) | ~$760 |
| CloudWatch logs (all 5 types) | ~$20–50 |

### Cost levers

| Lever | Saving | How |
|---|---|---|
| `capacity_type = "SPOT"` | 60–70% on EC2 | Use for dev/staging node groups |
| `az_count = 2` | ~10–15% cross-AZ transfer | Use for dev/staging |
| `desired_size = 1` per group | Proportional | Use for dev/staging |
| `cluster_log_types = []` | ~$20–50/month | Disable all logs in dev |
| No GPU group | ~$760/month | Omit `gpu` from `node_groups` map in dev/staging |

---

## Running Locally (Podman container)

```bash
# From aj-infra-context/local-testing/ (formerly My-Infra/ — repo renamed;
# note this local Podman workflow currently has no Makefile/Dockerfile, see
# that repo's local-testing/README.md for the known gap)
make shell

# Inside container
cd /workspaces/aj-tf-module-eks
terraform init -backend=false
terraform plan -var-file=example.tfvars
```

Dummy AWS credentials (`test`/`test`) and `skip_credentials_validation = true` in `providers.tf` allow `terraform plan` to work without real AWS access.

---

## Blue/Green Upgrade Playbook

```
1. Prod is running on BLUE (k8s 1.35)
2. terraform apply → provisions GREEN cluster (k8s 1.36)
3. Deploy workloads to GREEN, run smoke tests
4. Shift Route53 weighted record: blue=0, green=100
5. Monitor for 24–48h
6. terraform destroy → tears down BLUE
```

---

## Known TODOs

- [x] EKS access entries (replaces aws-auth ConfigMap — GA in 1.29+) — see `aws_eks_access_entry.*` in `main.tf`
- [ ] Windows node group support
- [ ] Bottlerocket AMI validation testing
- [ ] IPv6 dual-stack support

> Karpenter NodePool + EC2NodeClass intentionally do **not** belong here — they're GitOps-managed CRDs in `aj-cluster-baseline`, not Terraform resources (see `aj-infra-context/CLAUDE.md`'s architecture). Previously listed as a TODO in this repo by mistake.
