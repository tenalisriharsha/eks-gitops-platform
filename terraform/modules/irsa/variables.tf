variable "role_name" {
  description = "Name of the IAM role created for this service account."
  type        = string

  validation {
    condition     = length(var.role_name) > 0 && length(var.role_name) <= 64
    error_message = "role_name must be between 1 and 64 characters."
  }
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC identity provider (the eks module's oidc_provider_arn output)."
  type        = string
}

variable "oidc_provider_url" {
  description = "Host (no scheme) of the cluster's OIDC issuer (the eks module's oidc_provider_url output)."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the service account this role trusts."
  type        = string
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account this role trusts."
  type        = string
}

variable "policy_arns" {
  description = "ARNs of managed IAM policies to attach to the role."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags applied to the IAM role."
  type        = map(string)
  default     = {}
}
