variable "region" {
  description = "AWS region for the live test tables"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Name of the orders table (the decoy table and app role are derived from it)"
  type        = string
  default     = "orders-live-test"
}
