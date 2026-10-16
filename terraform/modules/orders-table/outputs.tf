output "table_name" {
  description = "DynamoDB table name (set as ORDERS_TABLE in the Helm values)"
  value       = aws_dynamodb_table.orders.name
}

output "table_arn" {
  description = "DynamoDB table ARN"
  value       = aws_dynamodb_table.orders.arn
}

output "role_arn" {
  description = "IRSA role ARN (set as the ServiceAccount's eks.amazonaws.com/role-arn annotation)"
  value       = aws_iam_role.app.arn
}
