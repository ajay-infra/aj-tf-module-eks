# skills.md — aj-tf-module-eks

## Purpose
Provisions an EKS cluster with managed node groups. Supports standalone and blue/green deployment modes. Configurable CNI (VPC CNI or Cilium) and Pod Identity.

## Type
`tf-module`

## Stable ref
```
source = "github.com/ajaylakma/aj-tf-module-eks?ref=eks-01"
```

## Deployment modes
- `standalone` — single cluster
- `blue-green` — paired clusters for zero-downtime upgrades

## Key inputs
| Variable | Description |
|---|---|
| `cluster_name` | EKS cluster name |
| `environment` | dev \| staging \| uat \| prod |
| `k8s_version` | Kubernetes version |
| `team` | Owning team slug |
| `eks_deployment_mode` | standalone \| blue-green |
| `vpc_id` | VPC to deploy into |
| `private_subnet_ids` | Node group subnets |
| `cni` | vpc-cni \| cilium |
| `pod_cidr` | Pod CIDR (Cilium mode) |

## Key outputs
| Output | Description |
|---|---|
| `cluster_name` | Cluster name |
| `cluster_endpoint` | API server endpoint |
| `cluster_ca_data` | CA certificate |
| `oidc_issuer` | OIDC provider URL (for Pod Identity / IRSA) |
| `cluster_security_group_id` | Cluster SG ID |
| `node_group_arns` | Node group ARNs |

## AWS tags applied
`Env`, `Team`, `ManagedBy`, `CostCenter`, `Model`, `Customer`

## Depends on
`aj-tf-module-vpc` — requires vpc_id and subnet_ids

## Branching convention
- `main` — active development
- `eks-01` — stable pinned release

## CI checks
fmt, validate, plan (dry-run), tfsec/checkov

## Agentic capabilities
- Detect K8s version drift vs latest supported
- Validate Pod Identity config vs IRSA usage
- Generate upgrade PR when new K8s version available
- Check CNI compatibility with K8s version
- Flag missing required tags
