module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  cluster_endpoint_public_access           = var.endpoint_public_access
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

  # Envelope-encrypt Kubernetes secrets with a module-managed KMS key
  cluster_encryption_config = { resources = ["secrets"] }

  cluster_addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = {}
    eks-pod-identity-agent = {}
  }

  eks_managed_node_groups = {
    general = {
      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size
      labels         = { workload = "general" }
    }
  }

  tags = var.tags
}
