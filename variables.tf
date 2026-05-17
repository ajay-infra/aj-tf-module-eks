# ── Core ─────────────────────────────────────────────────────────────────────

variable "cluster_name" {
  type        = string
  description = "EKS cluster name (e.g. 'ai-search-prod-blue')"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "k8s_version" {
  type        = string
  description = <<-EOT
    Kubernetes version for the EKS cluster (e.g. '1.35').
    EKS standard support lasts 14 months from release date — after that,
    extended support auto-applies at +$0.60/cluster/hour (~$438/month extra).
    Always use a version within its standard support window.
    Check current supported versions:
    https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
  EOT
  default     = "1.35"
}

# ── Tags ──────────────────────────────────────────────────────────────────────

variable "team" {
  type    = string
  default = "infra-core"
}

variable "cost_center" {
  type    = string
  default = "infra-2026-q1"
}

variable "common_tags" {
  type = map(string)
  default = {
    Project    = "ai-search"
    ManagedBy  = "Terraform"
    Repository = "aj-tf-module-eks"
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ── Deployment Mode ───────────────────────────────────────────────────────────

variable "eks_deployment_mode" {
  type        = string
  description = "standalone = single cluster; blue_green = color-tagged cluster for blue/green swap"
  default     = "blue_green"
  validation {
    condition     = contains(["standalone", "blue_green"], var.eks_deployment_mode)
    error_message = "eks_deployment_mode must be 'standalone' or 'blue_green'."
  }
}

variable "color" {
  type        = string
  description = "Cluster color in blue_green mode: 'blue' or 'green'"
  default     = "blue"
  validation {
    condition     = contains(["blue", "green"], var.color)
    error_message = "color must be 'blue' or 'green'."
  }
}

# ── Networking (from vpc module outputs) ─────────────────────────────────────

variable "vpc_id" {
  type        = string
  description = "VPC ID (from vpc module: blue_vpc_id or standalone vpc_id)"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs ordered by AZ (from vpc module). az_count controls how many are used."
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs ordered by AZ (from vpc module). az_count controls how many are used."
}

# ── AZ Count ──────────────────────────────────────────────────────────────────

variable "az_count" {
  type = number
  description = <<-EOT
    Number of Availability Zones to spread the cluster across.
      2 = cost-optimised dev/staging  (lower cross-AZ data-transfer costs, relaxed SLO)
      3 = standard HA production       (default — balanced cost vs resilience, 99.9% SLA)
      4 = high-resilience / regulated  (financial, healthcare, strict 99.99% SLA)
    Subnets in private_subnet_ids / public_subnet_ids must be ordered by AZ
    (standard output from aj-tf-module-vpc).
  EOT
  default = 3
  validation {
    condition     = contains([2, 3, 4], var.az_count)
    error_message = "az_count must be 2, 3, or 4."
  }
}

# ── CNI ───────────────────────────────────────────────────────────────────────

variable "cni" {
  type        = string
  description = <<-EOT
    CNI to use for pod networking:
      vpc-cni = AWS VPC CNI (default) — pods consume real VPC IPs from subnet CIDRs
      cilium  = Cilium overlay (VXLAN) — pods get IPs from pod_cidr, not VPC CIDR;
                replaces vpc-cni and kube-proxy addons automatically
  EOT
  default = "vpc-cni"
  validation {
    condition     = contains(["vpc-cni", "cilium"], var.cni)
    error_message = "cni must be 'vpc-cni' or 'cilium'."
  }
}

variable "pod_cidr" {
  type        = string
  description = <<-EOT
    Pod IP address pool for Cilium overlay mode (ignored when cni = 'vpc-cni').
    Must not overlap with VPC CIDR or Kubernetes service CIDR.
    Default 100.64.0.0/10 provides ~4M pod IPs and is RFC 6598 (carrier-grade NAT)
    space — safe to use even in enterprise environments.
  EOT
  default = "100.64.0.0/10"
}

# ── API Server Access ─────────────────────────────────────────────────────────

variable "endpoint_public_access" {
  type    = bool
  default = true
}

variable "endpoint_private_access" {
  type    = bool
  default = true
}

variable "public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

# ── Control Plane Logging ─────────────────────────────────────────────────────

variable "cluster_log_types" {
  type = list(string)
  description = <<-EOT
    EKS control plane log types to ship to CloudWatch Logs.
    Full set : ["api", "audit", "authenticator", "controllerManager", "scheduler"]
    Set to [] in dev to avoid CloudWatch ingestion costs (~$0.50/GB per type).
    Minimum recommended for prod: ["api", "audit"].
  EOT
  default = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

# ── Add-ons ───────────────────────────────────────────────────────────────────

variable "addons" {
  type = map(object({
    version           = optional(string)
    resolve_conflicts = optional(string, "OVERWRITE")
  }))
  default = {
    coredns            = {}
    kube-proxy         = {}
    vpc-cni            = {}
    pod-identity-agent = {}
    aws-ebs-csi-driver = {}
  }
}

# ── Node Groups ───────────────────────────────────────────────────────────────

variable "node_groups" {
  description = <<-EOT
    Map of node groups to create. The map key is used as the group name in
    resource names and the built-in "node-group" Kubernetes label.

    Required per group:
      instance_types  list of EC2 instance types (first match wins)
      desired_size    initial node count (ignored at runtime — Karpenter/HPA manage this)
      min_size        floor for cluster-autoscaler / Karpenter
      max_size        ceiling for cluster-autoscaler / Karpenter

    Optional per group:
      capacity_type   ON_DEMAND (default) | SPOT  — use SPOT for dev/batch to cut costs
      disk_size_gb    root EBS volume in GB (default 50; use 100+ for LLM model weights)
      ami_type        AL2_x86_64 (default) | AL2_x86_64_GPU | BOTTLEROCKET_x86_64 | etc.
      labels          extra Kubernetes node labels, merged with { node-group = <key> }
      taints          Kubernetes taints for workload isolation (e.g. GPU NoSchedule)
  EOT

  type = map(object({
    instance_types = list(string)
    desired_size   = number
    min_size       = number
    max_size       = number
    capacity_type  = optional(string, "ON_DEMAND")
    disk_size_gb   = optional(number, 50)
    ami_type       = optional(string, "AL2_x86_64")
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
  }))

  default = {
    frontend = {
      instance_types = ["m6i.xlarge"]
      desired_size   = 3
      min_size       = 2
      max_size       = 6
      labels = {
        workload = "frontend"
        role     = "general"
      }
    }
    backend = {
      instance_types = ["m6i.2xlarge"]
      desired_size   = 2
      min_size       = 1
      max_size       = 5
      labels = {
        workload = "backend"
        role     = "rag"
      }
    }
  }
}

# ── Pod Identity Associations ─────────────────────────────────────────────────

variable "pod_identity_associations" {
  description = <<-EOT
    Map of EKS Pod Identity associations. The map key becomes part of the IAM
    role name — use a short, stable identifier (e.g. "aws-lbc", "karpenter").
    Add any service account that needs AWS API access; no IRSA / OIDC required.

    policy_arns   list of managed or customer-managed policy ARNs to attach
    inline_policy optional raw JSON string for a single inline IAM policy
  EOT

  type = map(object({
    namespace            = string
    service_account_name = string
    policy_arns          = optional(list(string), [])
    inline_policy        = optional(string, "")
  }))

  default = {}
}
