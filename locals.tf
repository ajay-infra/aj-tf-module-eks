locals {
  name_prefix   = "${lower(replace(var.cluster_name, " ", "-"))}-${var.environment}"
  is_blue_green = var.eks_deployment_mode == "blue_green"

  # AZ-scoped subnets — sliced to az_count.
  # Subnets must be ordered by AZ (standard aj-tf-module-vpc output).
  # min() guards against callers passing fewer subnets than az_count.
  active_private_subnets = slice(var.private_subnet_ids, 0, min(var.az_count, length(var.private_subnet_ids)))
  active_public_subnets  = slice(var.public_subnet_ids, 0, min(var.az_count, length(var.public_subnet_ids)))

  # When using Cilium, strip vpc-cni and kube-proxy — Cilium's eBPF replaces both.
  # All other addons (coredns, pod-identity-agent, aws-ebs-csi-driver) are kept.
  effective_addons = var.cni == "cilium" ? {
    for k, v in var.addons : k => v if !contains(["vpc-cni", "kube-proxy"], k)
  } : var.addons

  full_tags = merge(var.common_tags, {
    Environment = var.environment
    Team        = var.team
    CostCenter  = var.cost_center
    ClusterName = var.cluster_name
    AZCount     = tostring(var.az_count)
  }, var.tags)
}
