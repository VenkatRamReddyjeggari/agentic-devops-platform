"""orders-api: a small service that gives the platform something real to deploy."""

from __future__ import annotations

import os
import threading
import time
from itertools import count

from flask import Flask, jsonify, request

app = Flask(__name__)

# In-memory store: state lives in one process. Gunicorn runs a single worker
# (threads share this dict) so a pod answers consistently, but data is per pod
# and lost on restart. Replace with a real datastore before relying on it.
_ORDERS: dict[int, dict] = {}
_IDS = count(1)
_LOCK = threading.Lock()
_STARTED = time.time()
VERSION = os.getenv("APP_VERSION", "dev")


@app.get("/healthz")
def healthz():
    """Liveness: the process is up."""
    return jsonify(status="ok")


@app.get("/readyz")
def readyz():
    """Readiness: the service can take traffic."""
    return jsonify(status="ready", version=VERSION, uptime_s=round(time.time() - _STARTED, 1))


@app.get("/orders")
def list_orders():
    with _LOCK:
        orders = list(_ORDERS.values())
    return jsonify(orders)


@app.post("/orders")
def create_order():
    body = request.get_json(silent=True) or {}
    item = body.get("item")
    qty = body.get("quantity", 1)
    if not isinstance(item, str) or not item.strip():
        return jsonify(error="'item' is required"), 400
    if not isinstance(qty, int) or qty < 1:
        return jsonify(error="'quantity' must be a positive integer"), 400
    with _LOCK:
        order_id = next(_IDS)
        order = {"id": order_id, "item": item.strip(), "quantity": qty, "status": "created"}
        _ORDERS[order_id] = order
    return jsonify(order), 201


@app.get("/orders/<int:order_id>")
def get_order(order_id: int):
    order = _ORDERS.get(order_id)
    if order is None:
        return jsonify(error="not found"), 404
    return jsonify(order)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
