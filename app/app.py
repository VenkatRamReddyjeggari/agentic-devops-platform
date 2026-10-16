"""orders-api: a small service that gives the platform something real to deploy."""

from __future__ import annotations

import logging
import os
import time
import uuid
from datetime import UTC, datetime
from functools import lru_cache

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError
from flask import Flask, jsonify, request

app = Flask(__name__)
log = logging.getLogger(__name__)

_STARTED = time.time()
VERSION = os.getenv("APP_VERSION", "dev")
MAX_ITEM_LEN = 200

# Fail fast instead of hanging a request thread on a slow or unreachable AWS API.
_BOTO_CONFIG = Config(
    connect_timeout=2, read_timeout=5, retries={"mode": "standard", "max_attempts": 3}
)


class OrderStore:
    """Orders in a DynamoDB table keyed by a string `id` (UUID).

    Credentials come from the default chain: IRSA in EKS, your profile locally.
    Set AWS_ENDPOINT_URL to point at DynamoDB Local.
    """

    def __init__(self, table: str, client=None) -> None:
        self.table = table
        # boto3 clients are thread-safe; resources are not, so use the client.
        self.client = client or boto3.client("dynamodb", config=_BOTO_CONFIG)

    @staticmethod
    def _to_order(item: dict) -> dict:
        return {
            "id": item["id"]["S"],
            "item": item["item"]["S"],
            "quantity": int(item["quantity"]["N"]),
            "status": item["status"]["S"],
            "created_at": item["created_at"]["S"],
        }

    def create(self, item: str, quantity: int) -> dict:
        order = {
            "id": str(uuid.uuid4()),
            "item": item,
            "quantity": quantity,
            "status": "created",
            "created_at": datetime.now(UTC).isoformat(),
        }
        self.client.put_item(
            TableName=self.table,
            Item={
                "id": {"S": order["id"]},
                "item": {"S": order["item"]},
                "quantity": {"N": str(order["quantity"])},
                "status": {"S": order["status"]},
                "created_at": {"S": order["created_at"]},
            },
            # Never overwrite an existing order, however unlikely a UUID clash is.
            ConditionExpression="attribute_not_exists(id)",
        )
        return order

    def get(self, order_id: str) -> dict | None:
        resp = self.client.get_item(
            TableName=self.table, Key={"id": {"S": order_id}}, ConsistentRead=True
        )
        item = resp.get("Item")
        return self._to_order(item) if item else None

    def list(self) -> list[dict]:
        # Full scan, oldest first: fine at demo scale. Add pagination params and a
        # GSI on created_at before this table holds more than a few thousand orders.
        orders: list[dict] = []
        for page in self.client.get_paginator("scan").paginate(TableName=self.table):
            orders.extend(self._to_order(i) for i in page["Items"])
        return sorted(orders, key=lambda o: o["created_at"])


@lru_cache(maxsize=1)
def store() -> OrderStore:
    table = os.getenv("ORDERS_TABLE")
    if not table:
        raise RuntimeError("ORDERS_TABLE is not set")
    return OrderStore(table)


@app.errorhandler(BotoCoreError)
@app.errorhandler(ClientError)
def storage_error(err: Exception):
    log.exception("DynamoDB call failed: %s", err)
    return jsonify(error="storage unavailable"), 503


@app.get("/healthz")
def healthz():
    """Liveness: the process is up."""
    return jsonify(status="ok")


@app.get("/readyz")
def readyz():
    """Readiness: the service is configured to take traffic.

    Deliberately does not call DynamoDB, so a brief AWS blip does not pull every
    pod out of the Service at once; request errors surface as 503s instead.
    """
    if not os.getenv("ORDERS_TABLE"):
        return jsonify(status="not ready", reason="ORDERS_TABLE is not set"), 503
    return jsonify(
        status="ready", version=VERSION, uptime_s=round(time.time() - _STARTED, 1)
    )


@app.get("/orders")
def list_orders():
    return jsonify(store().list())


@app.post("/orders")
def create_order():
    body = request.get_json(silent=True) or {}
    item = body.get("item")
    qty = body.get("quantity", 1)
    if not isinstance(item, str) or not item.strip():
        return jsonify(error="'item' is required"), 400
    if len(item.strip()) > MAX_ITEM_LEN:
        return jsonify(error=f"'item' must be at most {MAX_ITEM_LEN} characters"), 400
    # bool is a subclass of int; reject `true` as a quantity.
    if not isinstance(qty, int) or isinstance(qty, bool) or qty < 1:
        return jsonify(error="'quantity' must be a positive integer"), 400
    return jsonify(store().create(item.strip(), qty)), 201


@app.get("/orders/<order_id>")
def get_order(order_id: str):
    try:
        uuid.UUID(order_id)
    except ValueError:
        return jsonify(error="not found"), 404
    order = store().get(order_id)
    if order is None:
        return jsonify(error="not found"), 404
    return jsonify(order)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
