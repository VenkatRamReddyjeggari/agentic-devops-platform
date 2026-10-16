output "orders_table" {
  description = "Orders table the app reads and writes"
  value       = module.orders_table.table_name
}

output "decoy_table" {
  description = "Table the app role must be denied access to"
  value       = aws_dynamodb_table.decoy.name
}

output "app_role_arn" {
  description = "Least-privilege app role the live tests assume"
  value       = module.orders_table.role_arn
}

output "region" {
  description = "Region the tables live in"
  value       = var.region
}
