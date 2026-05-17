# ── EKS Control Plane + Add-ons ───────────────────────────────────────────────

module "eks_cluster" {
  source = "./modules/eks-cluster"

  name_prefix             = local.name_prefix
  cluster_name            = var.cluster_name
  k8s_version             = var.k8s_version
  vpc_id                  = var.vpc_id
  private_subnet_ids      = local.active_private_subnets
  public_subnet_ids       = local.active_public_subnets
  endpoint_public_access  = var.endpoint_public_access
  endpoint_private_access = var.endpoint_private_access
  public_access_cidrs     = var.public_access_cidrs
  cluster_log_types       = var.cluster_log_types
  addons                  = local.effective_addons
  tags                    = local.full_tags
}

# ── Node Groups (dynamic) ─────────────────────────────────────────────────────
# One aws_eks_node_group per entry in var.node_groups.
# Add, remove, or reconfigure node groups entirely from the calling tfvars —
# no changes to this file needed.

module "node_groups" {
  for_each = var.node_groups
  source   = "./modules/node-group"

  name_prefix            = local.name_prefix
  group_name             = each.key
  cluster_name           = module.eks_cluster.cluster_name
  private_subnet_ids     = local.active_private_subnets
  node_security_group_id = module.eks_cluster.node_security_group_id
  instance_types         = each.value.instance_types
  desired_size           = each.value.desired_size
  min_size               = each.value.min_size
  max_size               = each.value.max_size
  capacity_type          = each.value.capacity_type
  disk_size_gb           = each.value.disk_size_gb
  ami_type               = each.value.ami_type
  labels                 = each.value.labels
  taints                 = each.value.taints
  tags                   = local.full_tags
}

# ── Pod Identity Associations (dynamic) ───────────────────────────────────────
# One IAM role + aws_eks_pod_identity_association per entry.
# Add Velero, IRSA migrations, custom operators — no changes to this file needed.

module "pod_identity" {
  for_each = var.pod_identity_associations
  source   = "./modules/pod-identity"

  name_prefix          = local.name_prefix
  cluster_name         = module.eks_cluster.cluster_name
  namespace            = each.value.namespace
  service_account_name = each.value.service_account_name
  iam_policy_arns      = each.value.policy_arns
  inline_policy        = each.value.inline_policy
  tags                 = local.full_tags
}
