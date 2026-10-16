output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "kubeconfig_command" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "orders_table_name" {
  description = "DynamoDB table for orders-api (chart env.ORDERS_TABLE)"
  value       = module.orders_table.table_name
}

output "orders_api_role_arn" {
  description = "IRSA role for orders-api (chart serviceAccount annotation eks.amazonaws.com/role-arn)"
  value       = module.orders_table.role_arn
}

output "argocd_ui_command" {
  description = "Open the Argo CD UI on https://localhost:8443 (user admin; password from argocd_password_command)"
  value       = "kubectl port-forward -n argocd svc/argocd-server 8443:443"
}

output "argocd_password_command" {
  description = "Print the initial Argo CD admin password"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
