import boto3
import pytest
from botocore.exceptions import ClientError
from moto import mock_aws

import app as app_module
from app import app

TABLE = "orders-test"


@pytest.fixture()
def table(monkeypatch):
    """A fresh mocked DynamoDB table per test; no real AWS calls are made."""
    for var in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"):
        monkeypatch.setenv(var, "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.setenv("ORDERS_TABLE", TABLE)
    with mock_aws():
        boto3.client("dynamodb").create_table(
            TableName=TABLE,
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            BillingMode="PAY_PER_REQUEST",
        )
        app_module.store.cache_clear()
        yield
        app_module.store.cache_clear()


@pytest.fixture()
def client(table):
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def test_health(client):
    assert client.get("/healthz").json == {"status": "ok"}


def test_ready(client):
    body = client.get("/readyz").json
    assert body["status"] == "ready"
    assert "version" in body


def test_not_ready_without_table(client, monkeypatch):
    monkeypatch.delenv("ORDERS_TABLE")
    assert client.get("/readyz").status_code == 503


def test_create_and_get_order(client):
    resp = client.post("/orders", json={"item": "widget", "quantity": 3})
    assert resp.status_code == 201
    order = resp.json
    assert order["item"] == "widget" and order["quantity"] == 3
    assert order["status"] == "created" and order["created_at"]
    assert client.get(f"/orders/{order['id']}").json == order


def test_order_is_persisted_in_dynamodb(client):
    order = client.post("/orders", json={"item": "  gadget "}).json
    item = boto3.client("dynamodb").get_item(
        TableName=TABLE, Key={"id": {"S": order["id"]}}
    )
    assert item["Item"]["item"] == {"S": "gadget"}
    assert item["Item"]["quantity"] == {"N": "1"}


def test_orders_survive_a_new_store(client):
    """The point of the change: data outlives the process that wrote it."""
    order = client.post("/orders", json={"item": "widget"}).json
    app_module.store.cache_clear()  # as if the pod restarted
    assert client.get(f"/orders/{order['id']}").json == order


def test_list_orders_oldest_first(client):
    ids = [
        client.post("/orders", json={"item": f"item-{i}"}).json["id"] for i in range(3)
    ]
    assert [o["id"] for o in client.get("/orders").json] == ids


@pytest.mark.parametrize(
    "payload",
    [
        {},
        {"item": ""},
        {"item": "   "},
        {"item": "x" * 201},
        {"item": "x", "quantity": 0},
        {"item": "x", "quantity": "2"},
        {"item": "x", "quantity": True},
    ],
)
def test_create_order_validation(client, payload):
    assert client.post("/orders", json=payload).status_code == 400


@pytest.mark.parametrize(
    "order_id", ["00000000-0000-4000-8000-000000000000", "not-a-uuid", "1"]
)
def test_missing_order(client, order_id):
    assert client.get(f"/orders/{order_id}").status_code == 404


def test_region_comes_from_aws_region(table, monkeypatch):
    """boto3 ignores AWS_REGION on its own; the app must honour it (found by the live tests)."""
    monkeypatch.delenv("AWS_DEFAULT_REGION")
    monkeypatch.setenv("AWS_REGION", "eu-west-1")
    assert app_module.OrderStore("t").client.meta.region_name == "eu-west-1"


def test_region_falls_back_to_aws_default_region(table, monkeypatch):
    monkeypatch.delenv("AWS_REGION", raising=False)
    monkeypatch.setenv("AWS_DEFAULT_REGION", "ap-south-1")
    assert app_module.OrderStore("t").client.meta.region_name == "ap-south-1"


def test_storage_error_returns_503(client, monkeypatch):
    def boom(*_args, **_kwargs):
        raise ClientError({"Error": {"Code": "ThrottlingException"}}, "Scan")

    monkeypatch.setattr(app_module.store(), "list", boom)
    resp = client.get("/orders")
    assert resp.status_code == 503
    assert resp.json == {"error": "storage unavailable"}


def test_concurrent_creates_get_unique_ids(client):
    from concurrent.futures import ThreadPoolExecutor

    def create(i: int) -> str:
        with app.test_client() as c:
            return c.post("/orders", json={"item": f"item-{i}"}).json["id"]

    with ThreadPoolExecutor(max_workers=8) as pool:
        ids = list(pool.map(create, range(50)))
    assert len(set(ids)) == 50
    listed = {o["id"] for o in client.get("/orders").json}
    assert set(ids) <= listed
