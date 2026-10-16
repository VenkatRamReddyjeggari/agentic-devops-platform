# Live test environment: the real AWS pieces orders-api depends on, without EKS.
#   - the orders table and the app role (same orders-table module as dev/prod)
#   - a "decoy" table the app role must NOT be able to touch
# Cost: DynamoDB on-demand + IAM, effectively $0 at test volume. No VPC, EKS or NAT.
# State is local (throwaway sandbox): apply, run scripts/live-test.sh, destroy.

data "aws_caller_identity" "current" {}

locals {
  # Any IAM principal in this account that has sts:AssumeRole permission (e.g. the
  # admin running the tests) may assume the app role. Account root as principal
  # works for IAM users, roles and SSO sessions alike.
  test_runner = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
}

module "orders_table" {
  source = "../../modules/orders-table"

  table_name          = var.name_prefix
  trusted_role_arns   = [local.test_runner]
  deletion_protection = false # throwaway: must be destroyable
}

# Exists only so the tests can prove the app role is denied access to it.
# AWS-owned key encryption is on by default for DynamoDB; no PITR for a decoy.
#trivy:ignore:AWS-0024
#trivy:ignore:AWS-0025
resource "aws_dynamodb_table" "decoy" {
  name         = "${var.name_prefix}-decoy"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }
}
