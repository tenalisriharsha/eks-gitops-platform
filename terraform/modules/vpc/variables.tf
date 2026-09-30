variable "name" {
  description = "Name prefix applied to every resource created by this module."
  type        = string

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 32
    error_message = "name must be between 1 and 32 characters."
  }
}

variable "cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR block."
  }
}

variable "azs" {
  description = "Availability zones to spread subnets across. Must have at least 2 for EKS."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "azs must contain at least 2 availability zones (EKS requires subnets in >= 2 AZs)."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per AZ, in the same order as var.azs."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.azs)
    error_message = "public_subnet_cidrs must have exactly one entry per AZ in var.azs."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets, one per AZ, in the same order as var.azs."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.azs)
    error_message = "private_subnet_cidrs must have exactly one entry per AZ in var.azs."
  }
}

variable "single_nat_gateway" {
  description = "If true, create one NAT gateway shared by all private subnets (cheaper). If false, create one NAT gateway per AZ (more resilient)."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster name used to tag subnets with kubernetes.io/cluster/<name>. Leave empty to skip EKS tagging."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags applied to every resource created by this module."
  type        = map(string)
  default     = {}
}
