variable "table_name" {
  description = "DynamoDB table name; also prefixes the IRSA role name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS cluster OIDC provider ARN (module.eks.oidc_provider_arn), trusted by the IRSA role; null when there is no cluster"
  type        = string
  default     = null

  validation {
    condition     = var.oidc_provider_arn == null || can(regex("oidc-provider/", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be an IAM OIDC provider ARN (…:oidc-provider/<issuer>)."
  }
}

variable "namespace" {
  description = "Kubernetes namespace orders-api runs in (required with oidc_provider_arn)"
  type        = string
  default     = null
}

variable "service_account" {
  description = "Kubernetes ServiceAccount name orders-api runs as, i.e. the Helm release name (required with oidc_provider_arn)"
  type        = string
  default     = null
}

variable "trusted_role_arns" {
  description = "Extra IAM principal ARNs allowed to assume the app role with sts:AssumeRole (e.g. a live test runner); empty for EKS-only use"
  type        = list(string)
  default     = []
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key for table encryption; null uses the AWS-managed DynamoDB key"
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Block table deletion (turn off only to deliberately tear the table down)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags merged onto every resource"
  type        = map(string)
  default     = {}
}
