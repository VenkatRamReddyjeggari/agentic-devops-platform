# GitOps delivery for dev: Argo CD runs in the cluster and pulls the orders-api
# chart from GitHub, so CI never needs network access to the Kubernetes API.
# CI pushes images to ECR and commits the new tag to charts/orders-api/values-dev.yaml;
# Argo CD notices the commit and rolls it out.

data "aws_ecr_repository" "orders_api" {
  name = var.ecr_repository # created by terraform/bootstrap
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.9.6" # Argo CD v3.5.3

  values = [yamlencode({
    dex           = { enabled = false } # log in with the admin password; no SSO in dev
    notifications = { enabled = false }
  })]

  depends_on = [module.eks]
}

resource "helm_release" "orders_api_app" {
  name       = "orders-api-app"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.6"

  # Account-specific values (image registry, IRSA role) are injected here rather
  # than committed, so the public repo never contains the AWS account ID.
  values = [yamlencode({
    applications = {
      (var.orders_api_release) = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = var.gitops_repo_url
          targetRevision = var.gitops_revision
          path           = "charts/orders-api"
          helm = {
            valueFiles = ["values.yaml", "values-dev.yaml"]
            valuesObject = {
              image = { repository = data.aws_ecr_repository.orders_api.repository_url }
              serviceAccount = {
                annotations = { "eks.amazonaws.com/role-arn" = module.orders_table.role_arn }
              }
              ordersTable = { name = module.orders_table.table_name }
            }
          }
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = var.orders_api_namespace
        }
        syncPolicy = {
          automated   = { prune = true, selfHeal = true }
          syncOptions = ["CreateNamespace=true"]
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}
