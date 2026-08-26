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

# ── EKS Access Entries — IAM → K8s group mapping ──────────────────────────────
# Replaces aws-auth ConfigMap (deprecated in EKS 1.29+).
# Maps IAM Identity Center roles to K8s groups; ClusterRoles in k8s-manifests
# bind those groups to actual permissions.
#
# Standard entries (always created when role ARNs provided):
#   infra-lead     → AmazonEKSClusterAdminPolicy (system:masters equivalent)
#   infra-core     → K8s group: infra-core (bound to platform-deployer ClusterRole)
#   infra-readonly → K8s group: infra-readonly (bound to platform-viewer ClusterRole)
#   break-glass    → AmazonEKSClusterAdminPolicy (same mechanism as infra-lead)
#
# Additional entries can be passed via var.iam_access_entries for team service accounts.

resource "aws_eks_access_entry" "infra_lead" {
  count         = var.infra_lead_role_arn != "" ? 1 : 0
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = var.infra_lead_role_arn
  type          = "STANDARD"
  tags          = local.full_tags
}

resource "aws_eks_access_policy_association" "infra_lead_cluster_admin" {
  count         = var.infra_lead_role_arn != "" ? 1 : 0
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = var.infra_lead_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
  depends_on = [aws_eks_access_entry.infra_lead]
}

resource "aws_eks_access_entry" "infra_core" {
  count             = var.infra_core_role_arn != "" ? 1 : 0
  cluster_name      = module.eks_cluster.cluster_name
  principal_arn     = var.infra_core_role_arn
  type              = "STANDARD"
  kubernetes_groups = ["infra-core"]
  tags              = local.full_tags
}

resource "aws_eks_access_entry" "infra_readonly" {
  count             = var.infra_readonly_role_arn != "" ? 1 : 0
  cluster_name      = module.eks_cluster.cluster_name
  principal_arn     = var.infra_readonly_role_arn
  type              = "STANDARD"
  kubernetes_groups = ["infra-readonly"]
  tags              = local.full_tags
}

# One access entry per team's AJPlatformDeveloper-<team> IAM Identity Center
# role, each mapped to its own <team>-developers K8s group. Fixed 2026-08-25:
# there was previously no developer access entry of any kind here — roles.yaml
# and aj-tf-module-iam-identity-center each separately claimed a different,
# never-implemented mechanism for this (see that module's main.tf header
# comment for the full history). kubernetes_groups here must match exactly
# what register-namespace's generated RoleBinding subjects expect per team.
resource "aws_eks_access_entry" "team_developer" {
  for_each          = var.team_developer_role_arns
  cluster_name      = module.eks_cluster.cluster_name
  principal_arn     = each.value
  type              = "STANDARD"
  kubernetes_groups = ["${each.key}-developers"]
  tags              = local.full_tags
}

resource "aws_eks_access_entry" "break_glass" {
  count         = var.break_glass_role_arn != "" ? 1 : 0
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = var.break_glass_role_arn
  type          = "STANDARD"
  tags          = local.full_tags
}

resource "aws_eks_access_policy_association" "break_glass_cluster_admin" {
  count         = var.break_glass_role_arn != "" ? 1 : 0
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = var.break_glass_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
  depends_on = [aws_eks_access_entry.break_glass]
}

# Additional access entries for team service accounts or CI roles
resource "aws_eks_access_entry" "additional" {
  for_each          = { for e in var.iam_access_entries : e.principal_arn => e }
  cluster_name      = module.eks_cluster.cluster_name
  principal_arn     = each.value.principal_arn
  type              = "STANDARD"
  kubernetes_groups = each.value.kubernetes_groups
  tags              = local.full_tags
}
