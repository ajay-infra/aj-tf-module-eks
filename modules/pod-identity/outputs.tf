output "role_arn" {
  value = aws_iam_role.this.arn
}

output "role_name" {
  value = aws_iam_role.this.name
}

output "association_id" {
  value = aws_eks_pod_identity_association.this.association_id
}
