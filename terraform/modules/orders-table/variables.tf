variable "table_name" {
  description = "DynamoDB table name; also prefixes the IRSA role name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS cluster OIDC provider ARN (module.eks.oidc_provider_arn), trusted by the IRSA role"
  type        = string

  validation {
    condition     = can(regex("oidc-provider/", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be an IAM OIDC provider ARN (…:oidc-provider/<issuer>)."
  }
}

variable "namespace" {
  description = "Kubernetes namespace orders-api runs in"
  type        = string
}

variable "service_account" {
  description = "Kubernetes ServiceAccount name orders-api runs as (the Helm release name)"
  type        = string
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
