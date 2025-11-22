# tests/test_generate_ticket.py

import base64
import json
from fastapi.testclient import TestClient

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

from main import app  # <--- nur FastAPI importieren, NICHT den Public Key

client = TestClient(app)


def load_public_key():
    with open("tests/public.pem", "rb") as f:
        return serialization.load_pem_public_key(f.read())


def test_generate_ticket_signature_can_be_verified():
    # Public Key aus Datei laden
    public_key = load_public_key()

    # Beispiel-Input
    body = {
        "from_station": "Zürich HB",
        "to_station": "Bern",
        "from_datetime": "2025-11-22T10:00:00",
        "to_datetime": "2025-11-22T11:00:00",
        "ticket_type": "single",
        "validating_methode": "qr",
        "user_provided_id": "user-1234",
    }

    # Endpoint aufrufen
    response = client.put("/buy-ticket", json=body)
    assert response.status_code == 200

    data = response.json()
    payload = data["payload"]
    signature_b64 = data["sign"]

    # Signature dekodieren
    signature = base64.b64decode(signature_b64)

    # Payload konsistent serialisieren (genau wie in sign_data())
    encoded = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()

    # Verifikation — wenn ungültig: Exception
    public_key.verify(
        signature,
        encoded,
        padding.PKCS1v15(),
        hashes.SHA256()
    )

if __name__ == "__main__":
    test_generate_ticket_signature_can_be_verified()
