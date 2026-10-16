#!/usr/bin/env bash
# Run the live tests against the real AWS stack in terraform/envs/live-test.
# Prerequisites: that stack is applied (by a human), AWS credentials for the same
# account are configured, and app/requirements-dev.txt is installed (Python 3.12).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tf=(terraform -chdir="$root/terraform/envs/live-test")

out() { "${tf[@]}" output -raw "$1"; }
LIVE_ORDERS_TABLE="$(out orders_table)"
LIVE_DECOY_TABLE="$(out decoy_table)"
LIVE_APP_ROLE_ARN="$(out app_role_arn)"
AWS_REGION="$(out region)"
export LIVE_ORDERS_TABLE LIVE_DECOY_TABLE LIVE_APP_ROLE_ARN AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

echo "Live test against AWS ($AWS_REGION): table $LIVE_ORDERS_TABLE, app role ${LIVE_APP_ROLE_ARN##*/}"
exec "${PYTHON:-python3}" -m pytest -v -p no:cacheprovider "$root/tests/live"
