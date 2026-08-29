output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks_cluster.cluster_name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks_cluster.cluster_arn
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks_cluster.cluster_endpoint
}

output "cluster_ca_data" {
  description = "EKS cluster CA certificate data (base64)"
  value       = module.eks_cluster.cluster_ca_data
  sensitive   = true
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster"
  value       = module.eks_cluster.cluster_version
}

output "cluster_security_group_id" {
  description = "EKS control plane security group ID"
  value       = module.eks_cluster.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Shared node security group ID (used for additional SG rules)"
  value       = module.eks_cluster.node_security_group_id
}

output "oidc_issuer" {
  description = "EKS OIDC issuer URL (for reference — Pod Identity is used, not IRSA)"
  value       = module.eks_cluster.oidc_issuer
}

output "node_group_arns" {
  description = "Map of node group name → ARN for all provisioned node groups"
  value       = { for k, v in module.node_groups : k => v.node_group_arn }
}

output "node_role_arns" {
  description = "All node IAM role ARNs — needed for aws-auth ConfigMap (if used)"
  value       = [for k, v in module.node_groups : v.node_role_arn]
}

output "active_az_count" {
  description = "Number of AZs this cluster is spread across (controlled by az_count)"
  value       = var.az_count
}

output "active_private_subnets" {
  description = "Private subnet IDs in use — sliced to az_count from private_subnet_ids"
  value       = local.active_private_subnets
}

output "cni" {
  description = "CNI mode in use: 'vpc-cni' or 'cilium'"
  value       = var.cni
}

output "cilium_helm_values" {
  description = <<-EOT
    Helm values to pass when installing Cilium in the k8s-manifests layer.
    Null when cni = 'vpc-cni'.
    Usage: helm install cilium cilium/cilium --version <cilium_version> -f <(terraform output -json cilium_helm_values)
  EOT
  value = var.cni == "cilium" ? {
    "routingMode"                                 = "tunnel"
    "tunnelProtocol"                              = "vxlan"
    "ipam.mode"                                   = "cluster-pool"
    "ipam.operator.clusterPoolIPv4PodCIDRList[0]" = var.pod_cidr
    "kubeProxyReplacement"                        = "true"
    "k8sServiceHost"                              = module.eks_cluster.cluster_endpoint
    "k8sServicePort"                              = "443"
    "eni.enabled"                                 = "false"
    "hubble.relay.enabled"                        = "true"
    "hubble.ui.enabled"                           = "true"

    # ── East-west encryption ────────────────────────────────────────────────
    # Without this, pod-to-pod traffic crosses the VPC in plaintext. VPC
    # isolation is not encryption: anything with a foothold on the network path
    # — a compromised node, a misconfigured mirror, a peered VPC — sees it.
    #
    # WireGuard rather than IPsec: simpler key management (Cilium handles
    # rotation), lower overhead, and no IKE daemon to operate. Requires kernel
    # 5.6+ or the wireguard module, which AL2023 has.
    #
    # ⚠ MTU. This stacks on the vxlan tunnel above — roughly 50 bytes of vxlan
    # plus 60 of WireGuard. Cilium auto-detects and adjusts, but if traffic
    # starts failing for large payloads while small requests succeed, MTU is the
    # first thing to check.
    #
    # nodeEncryption stays off: it encrypts host-network traffic too, which
    # interferes with the health checks and node-level agents this estate runs.
    "encryption.enabled"        = "true"
    "encryption.type"           = "wireguard"
    "encryption.nodeEncryption" = "false"
  } : null
}

output "eks_deployment_mode" {
  description = "Deployment mode this cluster is configured for"
  value       = var.eks_deployment_mode
}

output "color" {
  description = "Cluster color (blue/green) — used for DNS routing decisions"
  value       = var.color
}
