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
