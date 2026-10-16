locals {
  # IRSA trust conditions key on the issuer host/path, i.e. the provider ARN minus its prefix.
  irsa        = var.oidc_provider_arn != null
  oidc_issuer = local.irsa ? element(split("oidc-provider/", var.oidc_provider_arn), 1) : null
}

# Encrypted with the AWS-managed DynamoDB key; pass kms_key_arn to use a CMK.
#trivy:ignore:AWS-0025
resource "aws_dynamodb_table" "orders" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  deletion_protection_enabled = var.deletion_protection

  tags = var.tags
}

data "aws_iam_policy_document" "assume" {
  # EKS pods: only the orders-api ServiceAccount in its namespace (IRSA).
  dynamic "statement" {
    for_each = local.irsa ? [1] : []
    content {
      actions = ["sts:AssumeRoleWithWebIdentity"]

      principals {
        type        = "Federated"
        identifiers = [var.oidc_provider_arn]
      }

      condition {
        test     = "StringEquals"
        variable = "${local.oidc_issuer}:sub"
        values   = ["system:serviceaccount:${var.namespace}:${var.service_account}"]
      }

      condition {
        test     = "StringEquals"
        variable = "${local.oidc_issuer}:aud"
        values   = ["sts.amazonaws.com"]
      }
    }
  }

  # Optional IAM principals (e.g. a live test runner) that may assume the role.
  dynamic "statement" {
    for_each = length(var.trusted_role_arns) > 0 ? [1] : []
    content {
      actions = ["sts:AssumeRole"]

      principals {
        type        = "AWS"
        identifiers = var.trusted_role_arns
      }
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.table_name}-app"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags

  lifecycle {
    precondition {
      condition     = local.irsa || length(var.trusted_role_arns) > 0
      error_message = "Set oidc_provider_arn (EKS/IRSA) and/or trusted_role_arns, or nothing can assume the role."
    }
    precondition {
      condition     = !local.irsa || (var.namespace != null && var.service_account != null)
      error_message = "namespace and service_account are required when oidc_provider_arn is set."
    }
  }
}

# Least privilege: only the calls orders-api makes, only on this table.
data "aws_iam_policy_document" "table" {
  statement {
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Scan"]
    resources = [aws_dynamodb_table.orders.arn]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn == null ? [] : [var.kms_key_arn]
    content {
      actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_role_policy" "table" {
  name   = "dynamodb-orders"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.table.json
}
