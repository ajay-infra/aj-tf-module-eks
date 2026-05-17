variable "name_prefix" {
  type        = string
  description = "Resource name prefix (e.g. myapp-prod-blue)"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name"
}

variable "k8s_version" {
  type        = string
  description = "Kubernetes version (e.g. '1.30')"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the cluster lives"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for EKS control plane ENIs"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs (for public endpoint access)"
}

variable "endpoint_public_access" {
  type        = bool
  description = "Enable public API server endpoint"
  default     = true
}

variable "endpoint_private_access" {
  type        = bool
  description = "Enable private API server endpoint"
  default     = true
}

variable "public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the public API endpoint"
  default     = ["0.0.0.0/0"]
}

variable "cluster_log_types" {
  type        = list(string)
  description = "EKS control plane log types to enable"
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "addons" {
  type = map(object({
    version           = optional(string)
    resolve_conflicts = optional(string, "OVERWRITE")
  }))
  description = "EKS managed add-ons to install"
  default = {
    coredns            = {}
    kube-proxy         = {}
    vpc-cni            = {}
    pod-identity-agent = {}
    aws-ebs-csi-driver = {}
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
