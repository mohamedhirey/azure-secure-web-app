import os

from azure.monitor.opentelemetry import configure_azure_monitor

# Must run before Flask is imported, or requests are not traced.
if os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    configure_azure_monitor()

from azure.cosmos import CosmosClient, exceptions  # noqa: E402
from azure.identity import ManagedIdentityCredential  # noqa: E402
from flask import Flask, abort, jsonify  # noqa: E402

app = Flask(__name__)
_container = None


def container():
    """Connect to Cosmos DB as the app's managed identity. No key, no password."""
    global _container
    if _container is None:
        client = CosmosClient(
            os.environ["COSMOS_ENDPOINT"],
            credential=ManagedIdentityCredential(client_id=os.environ["AZURE_CLIENT_ID"]),
        )
        database = client.get_database_client(os.environ["COSMOS_DATABASE"])
        _container = database.get_container_client(os.environ["COSMOS_CONTAINER"])
    return _container


@app.get("/")
def index():
    visits = container()
    try:
        counter = visits.read_item("counter", partition_key="counter")
    except exceptions.CosmosResourceNotFoundError:
        counter = {"id": "counter", "visits": 0}
    counter["visits"] += 1
    visits.upsert_item(counter)

    # If the Key Vault reference failed to resolve, the platform passes the raw
    # "@Microsoft.KeyVault(...)" text through instead of the secret.
    secret = os.getenv("DEMO_API_KEY", "")
    return jsonify(
        visits=counter["visits"],
        secret_from_key_vault=bool(secret) and not secret.startswith("@Microsoft.KeyVault"),
    )


@app.get("/health")
def health():
    return "ok"


@app.get("/fail")
def fail():
    """Returns a server error on purpose, to test the alert."""
    abort(500)
