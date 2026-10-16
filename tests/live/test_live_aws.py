"""Live tests against real AWS (DynamoDB + IAM), run by scripts/live-test.sh.

They need the terraform/envs/live-test stack applied and AWS credentials for the
account. Everything the app does runs as the least-privilege app role (assumed with
STS), exactly the permissions a pod gets through IRSA; the admin credentials are
used only to verify and clean up.
"""

from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

import boto3
import pytest
from botocore.exceptions import ClientError

APP_DIR = Path(__file__).resolve().parents[2] / "app"

REQUIRED = ("LIVE_ORDERS_TABLE", "LIVE_DECOY_TABLE", "LIVE_APP_ROLE_ARN", "AWS_REGION")
if missing := [v for v in REQUIRED if not os.getenv(v)]:
    pytest.skip(
        f"live tests need {', '.join(missing)} (run scripts/live-test.sh)",
        allow_module_level=True,
    )

ORDERS = os.environ["LIVE_ORDERS_TABLE"]
DECOY = os.environ["LIVE_DECOY_TABLE"]
ROLE_ARN = os.environ["LIVE_APP_ROLE_ARN"]
REGION = os.environ["AWS_REGION"]


# ---------- fixtures ----------


@pytest.fixture(scope="module")
def admin():
    return boto3.client("dynamodb", region_name=REGION)


@pytest.fixture(scope="module")
def role_creds():
    c = boto3.client("sts", region_name=REGION).assume_role(
        RoleArn=ROLE_ARN, RoleSessionName="orders-api-live-test"
    )["Credentials"]
    return {
        "aws_access_key_id": c["AccessKeyId"],
        "aws_secret_access_key": c["SecretAccessKey"],
        "aws_session_token": c["SessionToken"],
    }


@pytest.fixture(scope="module")
def app_ddb(role_creds):
    return boto3.client("dynamodb", region_name=REGION, **role_creds)


@pytest.fixture(scope="module")
def created(admin):
    """Ids written during the run; removed afterwards with admin credentials
    (the app role itself is not allowed to delete)."""
    ids: list[str] = []
    yield ids
    for i in ids:
        admin.delete_item(TableName=ORDERS, Key={"id": {"S": i}})


def denied(call) -> bool:
    try:
        call()
    except ClientError as e:
        return e.response["Error"]["Code"] in ("AccessDeniedException", "AccessDenied")
    return False


# ---------- IAM: what the app role may and may not do ----------


def test_runs_as_the_app_role(role_creds):
    arn = boto3.client("sts", region_name=REGION, **role_creds).get_caller_identity()[
        "Arn"
    ]
    assert f":assumed-role/{ROLE_ARN.rsplit('/', 1)[1]}/" in arn


def test_role_can_write_read_and_scan_its_table(app_ddb, created):
    probe = f"live-probe-{uuid.uuid4()}"
    created.append(probe)
    item = {
        "id": {"S": probe},
        "item": {"S": "probe"},
        "quantity": {"N": "1"},
        "status": {"S": "created"},
        "created_at": {"S": "2000-01-01T00:00:00+00:00"},
    }
    app_ddb.put_item(TableName=ORDERS, Item=item)
    got = app_ddb.get_item(
        TableName=ORDERS, Key={"id": {"S": probe}}, ConsistentRead=True
    )
    assert got["Item"]["item"] == {"S": "probe"}
    assert "Items" in app_ddb.scan(TableName=ORDERS, Limit=1)


def test_role_cannot_delete_from_its_table(app_ddb):
    assert denied(lambda: app_ddb.delete_item(TableName=ORDERS, Key={"id": {"S": "x"}}))


def test_role_cannot_read_or_write_another_table(app_ddb):
    assert denied(lambda: app_ddb.scan(TableName=DECOY))
    assert denied(lambda: app_ddb.get_item(TableName=DECOY, Key={"id": {"S": "x"}}))
    assert denied(lambda: app_ddb.put_item(TableName=DECOY, Item={"id": {"S": "x"}}))


def test_role_cannot_list_or_describe_tables(app_ddb):
    assert denied(lambda: app_ddb.list_tables())
    assert denied(lambda: app_ddb.describe_table(TableName=ORDERS))


# ---------- the real app on real DynamoDB ----------


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _call(method: str, url: str, body: dict | None = None) -> tuple[int, dict]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url, data=data, method=method, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


class Server:
    """orders-api under gunicorn, authenticated only as the app role."""

    def __init__(self, role_creds: dict) -> None:
        self.port = _free_port()
        self.base = f"http://127.0.0.1:{self.port}"
        # Drop the runner's own AWS identity (profile, keys) so the app can only act
        # as the role. AWS_ENDPOINT_URL is kept for dry runs against an emulator.
        env = {
            k: v
            for k, v in os.environ.items()
            if not k.startswith("AWS_") or k == "AWS_ENDPOINT_URL"
        }
        env.update(
            AWS_REGION=REGION,
            AWS_ACCESS_KEY_ID=role_creds["aws_access_key_id"],
            AWS_SECRET_ACCESS_KEY=role_creds["aws_secret_access_key"],
            AWS_SESSION_TOKEN=role_creds["aws_session_token"],
            ORDERS_TABLE=ORDERS,
        )
        self.proc = subprocess.Popen(
            [
                sys.executable,  # same interpreter (and installed gunicorn) as the tests
                "-m",
                "gunicorn",
                "--bind",
                f"127.0.0.1:{self.port}",
                "--workers",
                "2",
                "--threads",
                "4",
                "--worker-tmp-dir",
                "/tmp",
                "app:app",
            ],
            cwd=APP_DIR,
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        for _ in range(50):
            try:
                if _call("GET", f"{self.base}/readyz")[0] == 200:
                    return
            except OSError:
                pass
            time.sleep(0.2)
        self.stop()
        raise RuntimeError("server did not become ready")

    def stop(self) -> None:
        self.proc.terminate()
        self.proc.wait(timeout=10)


def test_order_is_stored_in_real_dynamodb(role_creds, admin, created):
    srv = Server(role_creds)
    try:
        status, order = _call(
            "POST", f"{srv.base}/orders", {"item": "live-widget", "quantity": 2}
        )
        assert status == 201
        created.append(order["id"])
        assert _call("GET", f"{srv.base}/orders/{order['id']}") == (200, order)
        assert order["id"] in {o["id"] for o in _call("GET", f"{srv.base}/orders")[1]}
    finally:
        srv.stop()
    # Verified independently of the app, straight from DynamoDB.
    item = admin.get_item(
        TableName=ORDERS, Key={"id": {"S": order["id"]}}, ConsistentRead=True
    )["Item"]
    assert item["item"] == {"S": "live-widget"} and item["quantity"] == {"N": "2"}


def test_order_survives_a_full_server_restart(role_creds, created):
    first = Server(role_creds)
    try:
        status, order = _call("POST", f"{first.base}/orders", {"item": "survivor"})
        assert status == 201
        created.append(order["id"])
    finally:
        first.stop()  # every worker process is gone: nothing left in memory

    second = Server(role_creds)
    try:
        assert _call("GET", f"{second.base}/orders/{order['id']}") == (200, order)
    finally:
        second.stop()


# Last on purpose: if IAM were ever too broad, this would really drop the table, so it
# must not run before the tests that need it.
def test_role_cannot_drop_its_table(app_ddb):
    assert denied(lambda: app_ddb.delete_table(TableName=ORDERS))
