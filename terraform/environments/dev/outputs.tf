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
