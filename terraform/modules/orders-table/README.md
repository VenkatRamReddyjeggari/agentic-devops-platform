# orders-table

DynamoDB table for orders-api plus the IRSA role its pods assume to use it.

- On-demand billing (`PAY_PER_REQUEST`): no capacity to size, ~$0 when idle.
- Point-in-time recovery on; deletion protection on by default.
- Encrypted at rest with the AWS-managed key, or a CMK via `kms_key_arn`.
- The role trusts only `system:serviceaccount:<namespace>:<service_account>` on the
  given cluster and may only `GetItem`, `PutItem` and `Scan` this table.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `table_name` | string | — | Table name; also prefixes the role name |
| `oidc_provider_arn` | string | `null` | `module.eks.oidc_provider_arn`; enables the IRSA trust |
| `namespace` | string | `null` | Namespace orders-api runs in (required with `oidc_provider_arn`) |
| `service_account` | string | `null` | ServiceAccount name, the Helm release name (required with `oidc_provider_arn`) |
| `trusted_role_arns` | list(string) | `[]` | Extra IAM principals allowed to assume the role (live tests) |
| `kms_key_arn` | string | `null` | CMK for encryption; null = AWS-managed key |
| `deletion_protection` | bool | `true` | Block table deletion |
| `tags` | map(string) | `{}` | Extra tags |

## Outputs

| Name | Description |
|---|---|
| `table_name` | Pass to the chart as `env.ORDERS_TABLE` |
| `table_arn` | Table ARN |
| `role_arn` | Pass to the chart as the `eks.amazonaws.com/role-arn` annotation |

## Example

```hcl
module "orders_table" {
  source = "../../modules/orders-table"

  table_name        = "platform-dev-orders"
  oidc_provider_arn = module.eks.oidc_provider_arn
  namespace         = "orders-api"
  service_account   = "orders-api"
}
```
