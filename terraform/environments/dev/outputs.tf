output "vpc_id" {
  description = "ID of the dev VPC."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs, for the EKS module's node groups (Phase 2)."
  value       = module.vpc.private_subnet_ids_list
}

output "public_subnet_ids" {
  description = "Public subnet IDs, for the EKS module's load balancers (Phase 2)."
  value       = module.vpc.public_subnet_ids_list
}

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "API server endpoint for the EKS cluster."
  value       = module.eks.cluster_endpoint
}

output "cluster_oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC identity provider, for wiring additional irsa modules."
  value       = module.eks.oidc_provider_arn
}

output "sample_app_irsa_role_arn" {
  description = "ARN of the IAM role for the sample app's Kubernetes service account."
  value       = module.irsa_sample_app.role_arn
}
