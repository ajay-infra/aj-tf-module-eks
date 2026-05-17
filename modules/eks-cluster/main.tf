# ── IAM Role — EKS Control Plane ─────────────────────────────────────────────

resource "aws_iam_role" "cluster" {
  name = "${var.name_prefix}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

# ── Security Group — Cluster (control plane) ──────────────────────────────────

resource "aws_security_group" "cluster" {
  name        = "${var.name_prefix}-cluster-sg"
  description = "EKS cluster control plane SG"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-cluster-sg" })
}

resource "aws_security_group" "nodes" {
  name        = "${var.name_prefix}-nodes-sg"
  description = "EKS node shared SG — allows node-to-node + node-to-cluster"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Node-to-node all traffic"
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id]
    description     = "Cluster API to nodes (webhooks)"
  }

  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id]
    description     = "Cluster to nodes (kubelet + pods)"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-nodes-sg" })
}

# Cluster SG ingress from nodes
resource "aws_security_group_rule" "cluster_from_nodes" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nodes.id
  security_group_id        = aws_security_group.cluster.id
  description              = "Nodes to cluster API"
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.k8s_version

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_public_access  = var.endpoint_public_access
    endpoint_private_access = var.endpoint_private_access
    public_access_cidrs     = var.public_access_cidrs
  }

  enabled_cluster_log_types = var.cluster_log_types

  # Ensure IAM role is ready before cluster
  depends_on = [aws_iam_role_policy_attachment.cluster_policy]

  tags = merge(var.tags, { Name = var.cluster_name })
}

# ── EKS Managed Add-ons ───────────────────────────────────────────────────────

resource "aws_eks_addon" "this" {
  for_each = var.addons

  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = each.key
  addon_version               = each.value.version
  resolve_conflicts_on_update = each.value.resolve_conflicts

  depends_on = [aws_eks_cluster.main]

  tags = var.tags
}
