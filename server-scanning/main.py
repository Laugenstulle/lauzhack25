import sqlite3
import os
import time
from fastapi import FastAPI, Body, HTTPException
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from uuid import UUID
from bcrypt import hashpw, gensalt
from pydantic import BaseModel
from routes import get_min_travel_time, ROUTES
import datetime
import base64
import json
import hashlib

app = FastAPI()

db_path = os.getenv('DB_PATH', 'tickets.db')
db_connection = sqlite3.connect(db_path, check_same_thread=False)
db_cursor = db_connection.cursor()

with open("private.pem", "rb") as f:
    PRIVATE_KEY = serialization.load_pem_private_key(f.read(), password=None)
with open("public.pem", "rb") as f:
    PUBLIC_KEY = serialization.load_pem_public_key(f.read())

db_cursor.execute('''
    CREATE TABLE IF NOT EXISTS tickets (
        id TEXT PRIMARY KEY,
        location TEXT,
        last_scan_time REAL
    )
''')


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


class TicketRegister(BaseModel):
    location: str


@app.put("/register/{ticket_id}")
async def register_ticket(ticket_id: UUID, payload: TicketRegister = Body(...)):
    current_time = time.time()
    salt = gensalt()

    ticket_bytes = ticket_id.bytes
    db_cursor.execute('SELECT id, location, last_scan_time FROM tickets')
    all_tickets = db_cursor.fetchall()

    found_hash = None
    last_location = None
    last_scan_time = None

    for hashed_ticket, loc, scan_time in all_tickets:
        if hashpw(ticket_bytes, hashed_ticket.encode('utf-8')) == hashed_ticket.encode('utf-8'):
            found_hash = hashed_ticket
            last_location = loc
            last_scan_time = scan_time
            break

    suspicious = False
    message = "Ticket registered successfully"

    if found_hash:
        # Ticket exists, check validation
        if last_location and last_scan_time:
            time_diff_minutes = (current_time - last_scan_time) / 60
            min_travel = get_min_travel_time(last_location, payload.location)

            if time_diff_minutes < min_travel:
                suspicious = True
                message = "Suspicious travel detected! Please verify ticket."

        # Update existing
        db_cursor.execute('UPDATE tickets SET location = ?, last_scan_time = ? WHERE id = ?',
                          (payload.location, current_time, found_hash))
    else:
        hashed_ticket = hashpw(ticket_id.bytes, salt).decode('utf-8')
        db_cursor.execute('INSERT INTO tickets (id, location, last_scan_time) VALUES (?, ?, ?)',
                          (hashed_ticket, payload.location, current_time))

    db_connection.commit()

    return {
        "message": message,
        "ticket": str(ticket_id),
        "location": payload.location,
        "suspicious": suspicious
    }


@app.get("/tickets/{ticket_id}")
async def exists_ticket(ticket_id: UUID):
    db_cursor.execute('SELECT id, location FROM tickets')
    tickets = db_cursor.fetchall()
    ticket_bytes = ticket_id.bytes

    for hashed_ticket, location in tickets:
        if hashpw(ticket_bytes, hashed_ticket.encode('utf-8')) == hashed_ticket.encode('utf-8'):
            return {"exists": True, "location": location}

    return {"exists": False}


def sign_data(payload: dict) -> str:
    encoded = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()

    signature = PRIVATE_KEY.sign(
        encoded,
        padding.PKCS1v15(),
        hashes.SHA256()
    )

    return base64.b64encode(signature).decode()


@app.get("/")
def read_root():
    return {"Welcome": "Lauzhack25"}


@app.put("/buy-ticket")
def generate_ticket(uptd: UserProvidedTicketData):
    if uptd.from_station not in ROUTES:
        raise HTTPException(status_code=404, detail="Start rail station not found!")
    if uptd.to_station not in ROUTES[uptd.from_station]:
        raise HTTPException(status_code=400,
                            detail=f"End rail station is not a valid connection for {uptd.from_station}!")
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
