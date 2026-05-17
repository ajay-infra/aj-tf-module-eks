variable "name_prefix" {
  type        = string
  description = "Resource name prefix"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name"
}

variable "service_account_name" {
  type        = string
  description = "Kubernetes service account name"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace of the service account"
}

variable "iam_policy_arns" {
  type        = list(string)
  description = "IAM policy ARNs to attach to the Pod Identity role"
  default     = []
}

variable "inline_policy" {
  type        = string
  description = "Optional inline IAM policy JSON"
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
