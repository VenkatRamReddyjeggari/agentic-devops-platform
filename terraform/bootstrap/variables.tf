variable "region" {
  description = "AWS region for the state bucket, lock table and ECR repository"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for bootstrap resource names; the state bucket also gets the account ID appended to be globally unique"
  type        = string
  default     = "platform"
}

variable "ecr_repository" {
  description = "ECR repository name for the orders-api image"
  type        = string
  default     = "orders-api"
}

variable "ecr_keep_images" {
  description = "Number of most recent images to keep in ECR; older ones expire"
  type        = number
  default     = 30
}

variable "github_repository" {
  description = "GitHub repository (owner/name) whose workflows may assume the CI role"
  type        = string
  default     = "VenkatRamReddyjeggari/agentic-devops-platform"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like owner/name."
  }
}

variable "release_branch" {
  description = "Only workflows running on this branch may assume the CI role"
  type        = string
  default     = "main"
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub Actions OIDC provider; set false if the account already has one (only one is allowed per account)"
  type        = bool
  default     = true
}
