variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster (used for resource naming and subnet tagging)."
  type        = string
  default     = "eks-gitops-dev"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the dev VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread the dev VPC across."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks, one per AZ."
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks, one per AZ."
  type        = list(string)
  default     = ["10.0.100.0/24", "10.0.101.0/24", "10.0.102.0/24"]
}

variable "single_nat_gateway" {
  description = "Use a single shared NAT gateway instead of one per AZ (cheaper, less resilient)."
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS control plane. Keep this on a version in EKS standard support; see docs/README.md for the upgrade path when it drifts."
  type        = string
  default     = "1.34"
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 3
}

variable "endpoint_public_access" {
  description = "Whether the EKS API server endpoint is reachable from outside the VPC. Set to false to use only the private endpoint (reach it from inside the VPC, e.g. through an SSM-managed instance)."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API endpoint, e.g. [\"203.0.113.10/32\"] for your own egress IP. Leave empty only together with allow_open_public_endpoint = true or endpoint_public_access = false."
  type        = list(string)
  default     = []
}

# OPT-IN, NOT A SAFE DEFAULT: dev keeps the API endpoint reachable from
# 0.0.0.0/0 so an existing checkout plans with no change and a fresh clone
# works without knowing your IP. Every plan prints a warning while this is
# on. To lock it down, set endpoint_public_access_cidrs to your egress IP(s)
# and this to false (see terraform.tfvars.example and docs/cluster-access.md).
variable "allow_open_public_endpoint" {
  description = "Explicitly allow the public EKS API endpoint to be open to 0.0.0.0/0. See the comment above this variable."
  type        = bool
  default     = true
}
