locals {
  name = "platform-dev"
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source = "../../modules/vpc"

  name               = local.name
  cidr               = var.vpc_cidr
  azs                = slice(data.aws_availability_zones.available.names, 0, 3)
  single_nat_gateway = true
}

module "eks" {
  source = "../../modules/eks"

  cluster_name           = local.name
  cluster_version        = var.cluster_version
  vpc_id                 = module.vpc.vpc_id
  subnet_ids             = module.vpc.private_subnet_ids
  endpoint_public_access = true

  node_capacity_type = "SPOT"
  node_min_size      = 1
  node_max_size      = 3
  node_desired_size  = 2
}
