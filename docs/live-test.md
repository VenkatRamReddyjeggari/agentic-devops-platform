# Live test on real AWS (about $0)

Tests orders-api against **real AWS DynamoDB and real IAM**, without EKS, a VPC or NAT
gateways, so it fits the free tier: DynamoDB on-demand costs fractions of a cent at test
volume, and IAM is free. Every step can be recorded.

## What it proves

All app traffic runs as the **least-privilege app role** (assumed with STS), the same
permissions a pod gets through IRSA in EKS. Admin credentials are used only to verify and
clean up.

| Test | Proves |
|---|---|
| `test_runs_as_the_app_role` | The tests really act as the app role, not as you |
| `test_role_can_write_read_and_scan_its_table` | The role has exactly what the app needs: `PutItem`, `GetItem`, `Scan` |
| `test_role_cannot_delete_from_its_table` | `DeleteItem` is **denied** |
| `test_role_cannot_read_or_write_another_table` | A different table (the decoy) is **denied** |
| `test_role_cannot_list_or_describe_tables` | `ListTables`, `DescribeTable` are **denied** |
| `test_order_is_stored_in_real_dynamodb` | The real app (gunicorn) stores an order, verified straight from DynamoDB |
| `test_order_survives_a_full_server_restart` | Stop every server process, start a new one: the order is still there |
| `test_role_cannot_drop_its_table` | `DeleteTable` is **denied** (runs last on purpose) |

## What gets created (`terraform/envs/live-test`)

| Resource | Notes |
|---|---|
| DynamoDB table `orders-live-test` | Same `orders-table` module as dev/prod; deletion protection **off** so it can be destroyed |
| IAM role `orders-live-test-app` | Same least-privilege policy as in EKS; trusted by IAM principals in this account instead of a cluster |
| DynamoDB table `orders-live-test-decoy` | Only exists so the tests can prove access to it is denied |

State is local (`terraform/envs/live-test/terraform.tfstate`, gitignored): this is a
throwaway sandbox.

## Run it

Prerequisites: `brew install awscli vhs`, `aws configure` with an admin user of your
account (in Terminal, never paste keys into chat), Python 3.12 with
`pip install -r app/requirements-dev.txt`.

| Step | Who | Command (from the repo root) | Recording |
|---|---|---|---|
| 1. Plan | Agent or you | `terraform -chdir=terraform/envs/live-test init && terraform -chdir=terraform/envs/live-test plan` | `vhs demo/tapes/04-live-plan.tape` |
| 2. Apply | **You** | `terraform -chdir=terraform/envs/live-test apply` | `vhs demo/tapes/05-live-apply.tape` |
| 3. Test | Agent or you | `bash scripts/live-test.sh` (set `PYTHON=` to a 3.12 interpreter if needed) | `PYTHON=… vhs demo/tapes/06-live-tests.tape` |
| 4. Destroy | **You** | `terraform -chdir=terraform/envs/live-test destroy` | `vhs demo/tapes/07-live-destroy.tape` |

Recordings are written to `demo-videos/` (gitignored). Steps 2 and 4 are yours because
the agent's guardrail hooks block `terraform apply` and `destroy`, including inside a
recording script.

Expected plan: **4 to add** (2 tables, 1 role, 1 role policy), 0 to change, 0 to destroy.

## Dry run without AWS

To check the test plumbing, run the suite against a local emulator
(`pip install 'moto[server]'`, `moto_server -p 5555`, create both tables, then export
`AWS_ENDPOINT_URL=http://127.0.0.1:5555` with the `LIVE_*` variables). The emulator does
not enforce IAM, so the four "denied" tests fail there by design; the other four must
pass.

The first dry run found a real bug: boto3 ignores `AWS_REGION` on its own, so the chart's
`ordersTable.region` setting never took effect. The app now reads `AWS_REGION` explicitly
(covered by `test_region_comes_from_aws_region`).
