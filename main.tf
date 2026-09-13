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
  secrets_kms_key_arn     = var.secrets_kms_key_arn
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

# ── EKS Access Entries — the group is the contract ───────────────────────────
# Replaces aws-auth (deprecated in EKS 1.29+). One entry per human group
# (identity-and-access-v1.md §6.1): the principal is the Identity Center
# reserved role for that group's permission set, IN THIS CLUSTER'S ACCOUNT —
# Identity Center provisions one such role into every assigned account, and
# a role ARN in any other account (the payer, say) authenticates nobody.
#
#   team-NNNN-read / team-NNNN-write / estate-read / estate-infra
#       STANDARD entry, kubernetes_groups = [<group>], no access policy —
#       aj-gitops/baseline/rbac binds estate-*; the workloads chart renders
#       the team RoleBindings per namespace from the record's `team:`
#   estate-admin / estate-break-glass
#       STANDARD entry + AmazonEKSClusterAdminPolicy, cluster scope — the
#       only cluster-admin in the estate, and never a ClusterRoleBinding
#
# v1.x had five named ARN variables with the same account bug in each; v2.0.0
# takes the map and nothing else.

locals {
  cluster_admin_groups = ["estate-admin", "estate-break-glass"]
}

resource "aws_eks_access_entry" "group" {
  for_each = var.access_groups

  cluster_name      = module.eks_cluster.cluster_name
  principal_arn     = each.value
  type              = "STANDARD"
  kubernetes_groups = contains(local.cluster_admin_groups, each.key) ? null : [each.key]
  tags              = merge(local.full_tags, { "access-group" = each.key })
}

resource "aws_eks_access_policy_association" "cluster_admin" {
  for_each = { for g, arn in var.access_groups : g => arn if contains(local.cluster_admin_groups, g) }

  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
  depends_on = [aws_eks_access_entry.group]
}

# Non-human principals — the hub's ArgoCD role, CI roles, service accounts
resource "aws_eks_access_entry" "additional" {
  for_each          = { for e in var.iam_access_entries : e.principal_arn => e }
  cluster_name      = module.eks_cluster.cluster_name
  principal_arn     = each.value.principal_arn
  type              = "STANDARD"
  kubernetes_groups = each.value.kubernetes_groups
  tags              = local.full_tags
}
