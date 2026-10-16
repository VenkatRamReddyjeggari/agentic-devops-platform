output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "kubeconfig_command" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "orders_table_name" {
  description = "DynamoDB table for orders-api (values-prod.yaml ordersTable.name)"
  value       = module.orders_table.table_name
}

output "orders_api_role_arn" {
  description = "IRSA role for orders-api (chart serviceAccount annotation eks.amazonaws.com/role-arn)"
  value       = module.orders_table.role_arn
}
