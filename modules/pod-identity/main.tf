# EKS Pod Identity — replaces IRSA (no OIDC provider needed)
# Pod Identity agent add-on must be installed on the cluster

resource "aws_iam_role" "this" {
  name = "${var.name_prefix}-${var.namespace}-${var.service_account_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  count      = length(var.iam_policy_arns)
  policy_arn = var.iam_policy_arns[count.index]
  role       = aws_iam_role.this.name
}

resource "aws_iam_role_policy" "inline" {
  count  = var.inline_policy != "" ? 1 : 0
  name   = "${var.name_prefix}-${var.service_account_name}-inline"
  role   = aws_iam_role.this.name
  policy = var.inline_policy
}

resource "aws_eks_pod_identity_association" "this" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account_name
  role_arn        = aws_iam_role.this.arn

  tags = var.tags
}
