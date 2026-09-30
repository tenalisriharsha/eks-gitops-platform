output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the created VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, keyed by availability zone."
  value       = { for az, subnet in aws_subnet.public : az => subnet.id }
}

output "private_subnet_ids" {
  description = "IDs of the private subnets, keyed by availability zone."
  value       = { for az, subnet in aws_subnet.private : az => subnet.id }
}

output "private_subnet_ids_list" {
  description = "IDs of the private subnets as a flat list, e.g. for EKS module node_group subnet_ids."
  value       = [for az in var.azs : aws_subnet.private[az].id]
}

output "public_subnet_ids_list" {
  description = "IDs of the public subnets as a flat list."
  value       = [for az in var.azs : aws_subnet.public[az].id]
}

output "nat_gateway_ids" {
  description = "IDs of the NAT gateway(s) created."
  value       = [for ng in aws_nat_gateway.this : ng.id]
}

output "internet_gateway_id" {
  description = "ID of the internet gateway."
  value       = aws_internet_gateway.this.id
}
