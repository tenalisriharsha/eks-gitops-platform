locals {
  node_sizes_valid = var.node_min_size <= var.node_desired_size && var.node_desired_size <= var.node_max_size

  # An empty public_access_cidrs list means 0.0.0.0/0 to the EKS API, so it
  # counts as open just like an explicit /0 entry.
  public_cidrs_open = length(var.endpoint_public_access_cidrs) == 0 || anytrue([
    for c in var.endpoint_public_access_cidrs : endswith(c, "/0")
  ])

  # Only send public_access_cidrs when the public endpoint is enabled. The
  # opt-in with no list writes 0.0.0.0/0 explicitly, which is the value AWS
  # already stores for clusters created without a list, so existing clusters
  # see no diff.
  public_access_cidrs = !var.endpoint_public_access ? null : (
    length(var.endpoint_public_access_cidrs) > 0 ? var.endpoint_public_access_cidrs : ["0.0.0.0/0"]
  )
}

resource "terraform_data" "validate_node_sizes" {
  lifecycle {
    precondition {
      condition     = local.node_sizes_valid
      error_message = "node sizing must satisfy node_min_size <= node_desired_size <= node_max_size."
    }
  }
}

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = local.public_access_cidrs
  }

  tags = var.tags

  depends_on = [aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy]

  lifecycle {
    precondition {
      condition     = var.endpoint_public_access || var.endpoint_private_access
      error_message = "At least one of endpoint_public_access or endpoint_private_access must be true, or nothing can reach the API server."
    }

    precondition {
      condition     = !(var.endpoint_public_access && local.public_cidrs_open) || var.allow_open_public_endpoint
      error_message = "The public EKS API endpoint would be open to the whole internet (endpoint_public_access_cidrs is empty or contains a /0 range). Set endpoint_public_access_cidrs to the ranges that need access, set endpoint_public_access = false and use the private endpoint, or set allow_open_public_endpoint = true to accept an open endpoint explicitly."
    }

    precondition {
      condition     = var.endpoint_public_access || length(var.endpoint_public_access_cidrs) == 0
      error_message = "endpoint_public_access_cidrs is set but endpoint_public_access is false, so the list would be ignored. Remove the CIDRs or enable the public endpoint."
    }
  }
}

resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  instance_types = var.node_instance_types
  capacity_type  = var.node_capacity_type
  disk_size      = var.node_disk_size

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly,
  ]
}

# IRSA requires an IAM OIDC identity provider trusting the cluster's own OIDC
# issuer. The thumbprint comes from the issuer's TLS certificate chain.
data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]

  tags = var.tags
}
