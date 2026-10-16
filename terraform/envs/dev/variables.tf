variable "region" {
  description = "AWS region for this environment"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR for this environment"
  type        = string
  default     = "10.10.0.0/16"
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the dev Kubernetes API (e.g. your VPN or office egress, as x.x.x.x/32)"
  type        = list(string)

  validation {
    condition     = length(var.api_allowed_cidrs) > 0 && !contains(var.api_allowed_cidrs, "0.0.0.0/0")
    error_message = "api_allowed_cidrs must list specific CIDRs, not 0.0.0.0/0."
  }
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

variable "ecr_repository" {
  description = "ECR repository holding the orders-api image (created by terraform/bootstrap)"
  type        = string
  default     = "orders-api"
}

variable "gitops_repo_url" {
  description = "Git repository Argo CD pulls the orders-api chart from"
  type        = string
  default     = "https://github.com/VenkatRamReddyjeggari/agentic-devops-platform.git"
}

variable "gitops_revision" {
  description = "Branch, tag or commit Argo CD tracks"
  type        = string
  default     = "main"
}
