# example.tfvars — used for terraform plan / CI validation
# Replace dummy subnet/vpc IDs with real outputs from aj-tf-module-vpc

# ── Core ──────────────────────────────────────────────────────────────────────
cluster_name        = "ai-search-dev-blue"
aws_region          = "us-east-1"
environment         = "dev"
k8s_version         = "1.35"
eks_deployment_mode = "blue_green"
color               = "blue"

# ── Networking (from vpc module outputs) ──────────────────────────────────────
# Pass ALL subnets from the VPC module ordered by AZ.
# az_count below controls how many are actually used.
vpc_id             = "vpc-0123456789abcdef0"
private_subnet_ids = ["subnet-aaa111", "subnet-bbb222", "subnet-ccc333", "subnet-ddd444"]
public_subnet_ids  = ["subnet-eee555", "subnet-fff666", "subnet-ggg777", "subnet-hhh888"]

# ── AZ Count ──────────────────────────────────────────────────────────────────
# 2 = dev / staging   — cost-optimised, relaxed SLO
# 3 = production      — standard HA (default)
# 4 = regulated prod  — financial / healthcare strict SLA
az_count = 2

# ── API Server ────────────────────────────────────────────────────────────────
endpoint_public_access  = true
endpoint_private_access = true
public_access_cidrs     = ["0.0.0.0/0"]

# ── CNI ───────────────────────────────────────────────────────────────────────
# vpc-cni = AWS default (pods consume VPC IPs)
# cilium  = overlay VXLAN (pods use pod_cidr, not VPC IPs) — recommended
cni      = "cilium"
pod_cidr = "100.64.0.0/10"
# cilium_version is owned by infra-platform (chart_version_cilium)

# ── Control Plane Logging ─────────────────────────────────────────────────────
# Dev: trim to [] or ["api","audit"] to reduce CloudWatch costs
cluster_log_types = ["api", "audit"]

# ── Node Groups ───────────────────────────────────────────────────────────────
# Define as many or as few groups as needed. Key = group name in K8s labels.
# capacity_type = SPOT for dev cost savings; ON_DEMAND for prod.
node_groups = {
  frontend = {
    instance_types = ["m6i.xlarge"]
    desired_size   = 1
    min_size       = 1
    max_size       = 3
    capacity_type  = "SPOT"
    labels = {
      workload = "frontend"
      role     = "general"
    }
  }

  backend = {
    instance_types = ["m6i.2xlarge"]
    desired_size   = 1
    min_size       = 1
    max_size       = 3
    capacity_type  = "SPOT"
    labels = {
      workload = "backend"
      role     = "rag"
    }
  }

  # GPU group — uncomment for prod inference workloads
  # gpu = {
  #   instance_types = ["g4dn.xlarge"]
  #   desired_size   = 2
  #   min_size       = 0
  #   max_size       = 4
  #   capacity_type  = "ON_DEMAND"
  #   ami_type       = "AL2_x86_64_GPU"
  #   disk_size_gb   = 100
  #   labels = {
  #     workload              = "gpu-inference"
  #     role                  = "llm"
  #     "nvidia.com/gpu.present" = "true"
  #   }
  #   taints = [{
  #     key    = "nvidia.com/gpu"
  #     value  = "true"
  #     effect = "NO_SCHEDULE"
  #   }]
  # }
}

# ── Pod Identity Associations ─────────────────────────────────────────────────
# Leave empty until IAM policies are created by infra-platform.
# Add any service account that needs AWS API access — no IRSA/OIDC needed.
pod_identity_associations = {
  # aws-lbc = {
  #   namespace            = "kube-system"
  #   service_account_name = "aws-load-balancer-controller"
  #   policy_arns          = ["arn:aws:iam::123456789012:policy/AWSLoadBalancerControllerIAMPolicy"]
  # }
  # karpenter = {
  #   namespace            = "kube-system"
  #   service_account_name = "karpenter"
  #   policy_arns          = ["arn:aws:iam::123456789012:policy/KarpenterControllerPolicy"]
  # }
  # external-secrets = {
  #   namespace            = "external-secrets"
  #   service_account_name = "external-secrets"
  #   policy_arns          = ["arn:aws:iam::123456789012:policy/ExternalSecretsPolicy"]
  # }
}

# ── Tags ──────────────────────────────────────────────────────────────────────
team        = "infra-core"
cost_center = "infra-2026-q1"
tags = {
  Owner = "ajay"
}
