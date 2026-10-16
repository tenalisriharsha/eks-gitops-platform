variable "cluster_name" {
  description = "Name of the EKS cluster. Also used as a prefix for the IAM roles and node group created by this module."
  type        = string

  validation {
    condition     = length(var.cluster_name) > 0 && length(var.cluster_name) <= 100
    error_message = "cluster_name must be between 1 and 100 characters."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS control plane. Keep this on a version in EKS standard support; see docs/README.md for the upgrade path when it drifts."
  type        = string
  default     = "1.34"
}

variable "subnet_ids" {
  description = "Subnet IDs for the EKS control plane's cross-account ENIs. Must span at least 2 AZs; typically the VPC's public + private subnets."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least 2 subnets (EKS requires subnets in >= 2 AZs)."
  }
}

variable "private_subnet_ids" {
  description = "Private subnet IDs where the managed node group's worker nodes are launched."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 1
    error_message = "private_subnet_ids must contain at least 1 subnet."
  }
}

variable "endpoint_private_access" {
  description = "Whether the EKS cluster API server endpoint is reachable from within the VPC."
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Whether the EKS cluster API server endpoint is reachable from outside the VPC. When true, endpoint_public_access_cidrs must list the allowed source ranges, unless allow_open_public_endpoint is set."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public API server endpoint (e.g. your office or VPN egress, as x.x.x.x/32). Leave empty when endpoint_public_access is false. Any /0 range (0.0.0.0/0, ::/0) is rejected unless allow_open_public_endpoint is true."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.endpoint_public_access_cidrs : can(cidrhost(c, 0))])
    error_message = "endpoint_public_access_cidrs must contain only valid CIDR blocks, e.g. 203.0.113.10/32."
  }
}

variable "allow_open_public_endpoint" {
  description = "Explicit opt-in to expose the public API server endpoint to the whole internet (0.0.0.0/0). Required when endpoint_public_access is true and endpoint_public_access_cidrs is empty or contains a /0 range. Access is still gated by IAM authentication, but the endpoint becomes reachable for scanning and credential attacks from anywhere."
  type        = bool
  default     = false
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes in the managed node group."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes in the managed node group."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes in the managed node group."
  type        = number
  default     = 3
}

variable "node_disk_size" {
  description = "Root EBS volume size (GiB) for worker nodes."
  type        = number
  default     = 20
}

variable "node_capacity_type" {
  description = "Capacity type for the managed node group: ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "tags" {
  description = "Additional tags applied to every resource created by this module."
  type        = map(string)
  default     = {}
}
