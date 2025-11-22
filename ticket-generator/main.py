import uuid
from typing import Union

from fastapi import FastAPI
from pydantic import BaseModel
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
import base64
import json
import hashlib

app = FastAPI()

with open("private.pem", "rb") as f:
    PRIVATE_KEY = serialization.load_pem_private_key(f.read(), password=None)
with open("public.pem", "rb") as f:
    PUBLIC_KEY = serialization.load_pem_public_key(f.read())

def sign_data(payload: dict) -> str:
    encoded = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()

    signature = PRIVATE_KEY.sign(
        encoded,
        padding.PKCS1v15(),
        hashes.SHA256()
    )

    return base64.b64encode(signature).decode()

class UserProvidedTicketData(BaseModel):
    from_station: str
    to_station: str
    from_datetime: str
    to_datetime: str
    ticket_type: str
    validating_methode: str
    user_provided_id: str

'''
class Ticket(BaseModel):
    from_station: str
    to_station: str
    from_datetime: str
    to_datetime: str
    ticket_type: str
    validating_methode: str
    ticket_id: str
    hash: str
'''
class Ticket(BaseModel):
    payload: dict
    signature: str
@app.get("/")
def read_root():
    return {"Welcome": "Lauzhack25"}

@app.put("/buy-ticket")
def generate_ticket(uptd: UserProvidedTicketData):
    random_ticket_number = str(uuid.uuid4())
    payload = {
        "from_station": uptd.from_station,
        "to_station": uptd.to_station,
        "from_datetime": uptd.from_datetime,
        "to_datetime": uptd.to_datetime,
        "ticket_type": uptd.ticket_type,
        "validating_methode": uptd.validating_methode,
        "price": 20,
        "random-ticket-number": random_ticket_number,
        "ticket-hash": hashlib.sha256((uptd.user_provided_id + random_ticket_number).encode()).hexdigest()
    }
    print(payload)
    return {"payload": payload, "sign": sign_data(payload)}

@app.get("/public-key")
def get_data():
    pem = PUBLIC_KEY.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return {"public-key": pem.decode("utf-8")}