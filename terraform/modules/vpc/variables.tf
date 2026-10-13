variable "name" {
  description = "Name prefix for the VPC and its resources"
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block (a /16 is expected; subnets are carved from it)"
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr, 0))
    error_message = "cidr must be a valid IPv4 CIDR block."
  }
}

variable "azs" {
  description = "Availability zones to spread subnets across (2-3 recommended)"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway (cheaper, dev) instead of one per AZ (HA, prod)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags merged onto every resource"
  type        = map(string)
  default     = {}
}
