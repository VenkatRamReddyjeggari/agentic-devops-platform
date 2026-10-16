terraform {
  required_version = ">= 1.6"

  # Local state on purpose: this root creates the remote-state bucket. Keep the
  # terraform.tfstate file safe (it is gitignored) or migrate it into the bucket after the first apply.

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Environment = "shared"
      ManagedBy   = "terraform"
      Repository  = "agentic-devops-platform"
    }
  }
}
