variable "region" {
  description = "AWS region for this environment"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR for this environment"
  type        = string
  default     = "10.20.0.0/16"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane"
  type        = string
  default     = "1.31"
}

variable "orders_api_namespace" {
  description = "Kubernetes namespace orders-api is deployed to (helm -n)"
  type        = string
  default     = "orders-api"
}

variable "orders_api_release" {
  description = "Helm release name for orders-api; the chart names its ServiceAccount after it"
  type        = string
  default     = "orders-api"
}
