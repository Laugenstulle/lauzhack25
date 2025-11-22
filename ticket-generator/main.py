import uuid
import datetime
import sys
sys.path.append('../server-scanning')
from routes import ROUTES

from fastapi import FastAPI, HTTPException
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
    from_datetime: int
    to_datetime: int
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

    if uptd.from_station not in ROUTES:
        raise HTTPException(status_code=404, detail="Start rail station not found!")
    if uptd.to_station not in ROUTES[uptd.from_station]:
        raise HTTPException(status_code=400, detail=f"End rail station is not a valid connection for {uptd.from_station}!")
    if uptd.from_datetime < datetime.datetime.now().timestamp() or uptd.to_datetime < datetime.datetime.now().timestamp():
        raise HTTPException(status_code=400, detail="Please book a connection that is not in the past.")
    if uptd.from_datetime > uptd.to_datetime:
        raise HTTPException(status_code=400, detail="The start time must be before the end time!")

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

@app.get("/routes")
def get_routes():
    print(ROUTES)
    response = {}
    for route in ROUTES.keys():
        response[route] = list(ROUTES[route].keys())
    return {"routes": response}

@app.get("/public-key")
def get_data():
    pem = PUBLIC_KEY.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return {"public-key": pem.decode("utf-8")}