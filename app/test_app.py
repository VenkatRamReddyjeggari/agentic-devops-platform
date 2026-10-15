import pytest

from app import app


@pytest.fixture()
def client():
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def test_health(client):
    assert client.get("/healthz").json == {"status": "ok"}


def test_ready(client):
    body = client.get("/readyz").json
    assert body["status"] == "ready"
    assert "version" in body


def test_create_and_get_order(client):
    resp = client.post("/orders", json={"item": "widget", "quantity": 3})
    assert resp.status_code == 201
    order = resp.json
    assert order["item"] == "widget" and order["quantity"] == 3
    assert client.get(f"/orders/{order['id']}").json == order


@pytest.mark.parametrize(
    "payload",
    [{}, {"item": ""}, {"item": "x", "quantity": 0}, {"item": "x", "quantity": "2"}],
)
def test_create_order_validation(client, payload):
    assert client.post("/orders", json=payload).status_code == 400


def test_missing_order(client):
    assert client.get("/orders/99999").status_code == 404


def test_concurrent_creates_get_unique_ids(client):
    from concurrent.futures import ThreadPoolExecutor

    def create(i: int) -> int:
        with app.test_client() as c:
            return c.post("/orders", json={"item": f"item-{i}"}).json["id"]

    with ThreadPoolExecutor(max_workers=8) as pool:
        ids = list(pool.map(create, range(50)))
    assert len(set(ids)) == 50
    listed = {o["id"] for o in client.get("/orders").json}
    assert set(ids) <= listed
