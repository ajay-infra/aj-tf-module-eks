# CLAUDE.md — aj-tf-module-eks

> Local context file for Claude Code. Not pushed to GitHub.

---

## What This Module Does

Provisions an EKS cluster optimized for AI inference workloads. Blue/green aware — each cluster is a standalone unit (blue or green) that connects to the shared data VPC via peering (from aj-tf-module-vpc).

---

## Where It Fits

**Architecture layer:** L4 — Compute
**Provisioned by:** `aj-infra-release` — `provision-eks.yml` (Stage 2) or `provision-central.yml` (Stage 2)
**Depends on:** `aj-tf-module-vpc` outputs (vpc_id, subnet IDs) passed in as `-var` flags
**State key pattern:** `workload/blue-green/<env>/eks-blue/terraform.tfstate` or `central/<tier>/eks/terraform.tfstate`

## How to Use

Triggered automatically as Stage 2 of `provision-eks.yml` in aj-infra-release after the VPC stage completes.

tfvars files to configure:
- `aj-infra-release/envs/workload/blue-green/<env>/eks-blue.tfvars` — blue cluster config
- `aj-infra-release/envs/workload/blue-green/<env>/eks-green.tfvars` — green cluster config (used during upgrade)
- `aj-infra-release/envs/workload/standalone/<env>/eks.tfvars` — standalone cluster config

GitHub secrets required:
- `TF_STATE_BUCKET`, `AWS_DEPLOY_ROLE_ARN`

Outputs consumed downstream:
- `aj-infra-platform` reads EKS remote state via `data.terraform_remote_state.eks`
- `aj-infra-central` reads central EKS state to get cluster endpoint for Helm provider

---

## Deployment Modes

### `standalone`
Single cluster. Used for dev/staging or in-place K8s patch upgrades (e.g. 1.30.1 → 1.30.2).

### `blue_green`
One cluster per color. Caller provisions blue first, then green when upgrading K8s minor versions. Traffic shifted via Route53 weighted records in infra-platform/dns/.

**K8s upgrade rule:**
- Patch upgrade (1.30.x → 1.30.y) → in-place OK
- Minor upgrade (1.30 → 1.31) → blue/green MANDATORY
- Major EKS add-on changes → blue/green MANDATORY

---

## Module Structure

```
modules/
  eks-cluster/   → EKS control plane + managed add-ons + 2 SGs (cluster + nodes)
  node-group/    → reusable node group resource — called via for_each from root
  pod-identity/  → aws_iam_role + aws_eks_pod_identity_association (not IRSA)
```

Root orchestrates: eks-cluster → module.node_groups (for_each over var.node_groups) → module.pod_identity (for_each over var.pod_identity_associations)

---

## Key Design Decisions

- **Pod Identity not IRSA** — no OIDC provider limit, simpler trust policy, reusable across clusters
- **m6i not t3** — no CPU credit bursting under RAG/LLM sustained load
- **GPU taint** — `nvidia.com/gpu=true:NoSchedule` prevents non-GPU pods landing on g4dn nodes
- **SSM not SSH** — no EC2 key pairs; all node access via SSM Session Manager (AmazonSSMManagedInstanceCore attached)
- **lifecycle ignore desired_size** — Karpenter/HPA manage scaling, Terraform only sets initial values
- **Dynamic node groups via for_each** — node groups are fully defined in tfvars; no changes to main.tf needed to add/remove groups
- **Dynamic pod identity via for_each** — any service account can be added via tfvars map; no hardcoded modules
- **az_count controls subnet slicing** — pass all VPC subnets, module slices to requested AZ count; subnets must be ordered by AZ (standard vpc module output)
- **disk_size 100GB on GPU nodes** — model weights (Ollama, vLLM) are large; set per node group via disk_size_gb
- **cluster_log_types tunable** — set to [] in dev to avoid CloudWatch costs; minimum ["api","audit"] for prod

---

## Variables to Know

- `az_count` — 2 (dev/staging), 3 (prod default), 4 (regulated/high-SLA); slices subnet lists from vpc module
- `node_groups` — map of node groups; key = group name in K8s labels + resource names; supports capacity_type (SPOT/ON_DEMAND), disk_size_gb, ami_type, labels, taints per group
- `pod_identity_associations` — map of Pod Identity associations; add any service account that needs AWS access
- `cluster_log_types` — list of control plane log types; set to [] in dev, ["api","audit"] minimum for prod
- `color` — "blue" or "green", drives naming in blue_green mode
- `eks_deployment_mode` — same pattern as vpc module

---

## Outputs Used by Downstream Modules

infra-platform/main.tf will consume:
- `cluster_name` → kubeconfig, ArgoCD cluster registration
- `cluster_endpoint` + `cluster_ca_data` → kubeconfig
- `node_security_group_id` → additional SG rules (e.g. Aurora access)
- `node_role_arns` → aws-auth ConfigMap (if EKS access entries not used)
- `node_group_arns` → map of group name → ARN (replaces old node_group_a/b/c_arn)
- `active_private_subnets` → subnet IDs actually used (sliced to az_count)
- `active_az_count` → number of AZs in use
- `color` → Route53 DNS weight decisions

---

## Running Locally (Podman container)

```bash
make shell                          # from My-Infra/
cd /workspaces/aj-tf-module-eks
terraform init -backend=false
terraform plan -var-file=example.tfvars
```

Dummy AWS creds (`test`/`test`) + `skip_credentials_validation = true` in providers.tf — plan works without real AWS.

---

## Known TODOs

- [ ] EKS access entries (replaces aws-auth ConfigMap — GA in 1.29+)
- [ ] Karpenter NodePool + EC2NodeClass resources (Helm in add-ons, NodePool in k8s-manifests)
- [ ] Cluster autoscaler alternative evaluation (Karpenter preferred)
- [ ] Windows node group support (future)
- [ ] Bottlerocket AMI option (security-hardened alternative to AL2)
- [ ] IPv6 dual-stack support
