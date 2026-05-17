variable "name_prefix" {
  type        = string
  description = "Resource name prefix"
}

variable "group_name" {
  type        = string
  description = "Node group label: 'a', 'b', or 'c'"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name to attach this node group to"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets for node group placement"
}

variable "node_security_group_id" {
  type        = string
  description = "Shared node security group ID from eks-cluster module"
}

variable "instance_types" {
  type        = list(string)
  description = "EC2 instance types for this node group"
}

variable "desired_size" {
  type        = number
  description = "Desired number of nodes"
}

variable "min_size" {
  type        = number
  description = "Minimum number of nodes"
}

variable "max_size" {
  type        = number
  description = "Maximum number of nodes"
}

variable "disk_size_gb" {
  type        = number
  description = "Root EBS volume size in GB"
  default     = 50
}

variable "capacity_type" {
  type        = string
  description = "ON_DEMAND or SPOT"
  default     = "ON_DEMAND"
}

variable "ami_type" {
  type        = string
  description = "AMI type: AL2_x86_64, AL2_x86_64_GPU, BOTTLEROCKET_x86_64, etc."
  default     = "AL2_x86_64"
}

variable "labels" {
  type        = map(string)
  description = "Kubernetes labels applied to all nodes in this group"
  default     = {}
}

variable "taints" {
  type = list(object({
    key    = string
    value  = optional(string)
    effect = string
  }))
  description = "Kubernetes taints applied to all nodes in this group"
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
