import sqlite3
import os
import time
import uuid
import hashlib
import base64
import json
import datetime
from uuid import UUID

from fastapi import FastAPI, Body, HTTPException
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from bcrypt import hashpw, gensalt
from pydantic import BaseModel

from routes import get_min_travel_time, ROUTES

# Constants
DB_PATH = os.getenv('DB_PATH', 'tickets.db')
PRIVATE_KEY_PATH = "private.pem"
PUBLIC_KEY_PATH = "public.pem"
# Just for demo purposes
TICKET_PRICE = 20

# App initialization
app = FastAPI()

# Database setup
db_connection = sqlite3.connect(DB_PATH, check_same_thread=False)
db_cursor = db_connection.cursor()

# Load cryptographic keys
with open(PRIVATE_KEY_PATH, "rb") as f:
    PRIVATE_KEY = serialization.load_pem_private_key(f.read(), password=None)

with open(PUBLIC_KEY_PATH, "rb") as f:
    PUBLIC_KEY = serialization.load_pem_public_key(f.read())

# Database initialization
db_cursor.execute('''
    CREATE TABLE IF NOT EXISTS tickets (
        id TEXT PRIMARY KEY,
        location TEXT,
        last_scan_time REAL
    )
''')


# Models
class UserProvidedTicketData(BaseModel):
    from_station: str
    to_station: str
    from_datetime: int
    to_datetime: int
    ticket_type: str
    validating_methode: str
    user_provided_id: str


class Ticket(BaseModel):
    payload: dict
    signature: str


class TicketRegister(BaseModel):
    location: str


# Helper functions
def sign_data(payload: dict) -> str:
    """Sign payload with private key."""
    encoded = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
    signature = PRIVATE_KEY.sign(encoded, padding.PKCS1v15(), hashes.SHA256())
    return base64.b64encode(signature).decode()


def find_ticket_in_db(ticket_bytes: bytes) -> tuple:
    """Find ticket in database by comparing hashed values."""
    db_cursor.execute('SELECT id, location, last_scan_time FROM tickets')
    all_tickets = db_cursor.fetchall()

    for hashed_ticket, loc, scan_time in all_tickets:
        if hashpw(ticket_bytes, hashed_ticket.encode('utf-8')) == hashed_ticket.encode('utf-8'):
            return hashed_ticket, loc, scan_time

    return None, None, None


def validate_travel_time(last_location: str, current_location: str, last_scan_time: float) -> bool:
    """Check if travel time is suspicious."""
    time_diff_minutes = (time.time() - last_scan_time) / 60
    min_travel = get_min_travel_time(last_location, current_location)
    return time_diff_minutes < min_travel


# Routes
@app.get("/")
def read_root():
    """Welcome endpoint."""
    return {"Welcome": "Lauzhack25"}


@app.put("/buy-ticket")
def generate_ticket(uptd: UserProvidedTicketData):
    """Generate a new ticket with signature."""
    # Validate stations
    if uptd.from_station not in ROUTES:
        raise HTTPException(status_code=404, detail="Start rail station not found!")

    if uptd.to_station not in ROUTES[uptd.from_station]:
        raise HTTPException(
            status_code=400,
            detail=f"End rail station is not a valid connection for {uptd.from_station}!"
        )

    # Validate times
    current_timestamp = datetime.datetime.now().timestamp()
    if uptd.from_datetime < current_timestamp or uptd.to_datetime < current_timestamp:
        raise HTTPException(status_code=400, detail="Please book a connection that is not in the past.")

    if uptd.from_datetime > uptd.to_datetime:
        raise HTTPException(status_code=400, detail="The start time must be before the end time!")

    # Generate ticket
    random_ticket_number = str(uuid.uuid4())
    ticket_hash = hashlib.sha256(
        (uptd.user_provided_id + random_ticket_number).encode()
    ).hexdigest()

    payload = {
        "from_station": uptd.from_station,
        "to_station": uptd.to_station,
        "from_datetime": uptd.from_datetime,
        "to_datetime": uptd.to_datetime,
        "ticket_type": uptd.ticket_type,
        "validating_methode": uptd.validating_methode,
        "price": TICKET_PRICE,
        "random-ticket-number": random_ticket_number,
        "ticket-hash": ticket_hash
    }

    return {"payload": payload, "sign": sign_data(payload)}


@app.put("/register/{ticket_id}")
async def register_ticket(ticket_id: UUID, payload: TicketRegister = Body(...)):
    """Register or update ticket scan."""
    current_time = time.time()
    ticket_bytes = ticket_id.bytes

    found_hash, last_location, last_scan_time = find_ticket_in_db(ticket_bytes)

    suspicious = False
    message = "Ticket registered successfully"

    if found_hash:
        # Validate travel time if previous scan exists
        if last_location and last_scan_time:
            if validate_travel_time(last_location, payload.location, last_scan_time):
                suspicious = True
                message = "Suspicious travel detected! Please verify ticket."

        # Update existing ticket
        db_cursor.execute(
            'UPDATE tickets SET location = ?, last_scan_time = ? WHERE id = ?',
            (payload.location, current_time, found_hash)
        )
    else:
        # Insert new ticket
        salt = gensalt()
        hashed_ticket = hashpw(ticket_bytes, salt).decode('utf-8')
        db_cursor.execute(
            'INSERT INTO tickets (id, location, last_scan_time) VALUES (?, ?, ?)',
            (hashed_ticket, payload.location, current_time)
        )

    db_connection.commit()

    return {
        "message": message,
        "ticket": str(ticket_id),
        "location": payload.location,
        "suspicious": suspicious,
    }


@app.get("/tickets/{ticket_id}")
async def exists_ticket(ticket_id: UUID):
    """Check if ticket exists in database."""
    ticket_bytes = ticket_id.bytes
    found_hash, location, _ = find_ticket_in_db(ticket_bytes)

    if found_hash:
        return {"exists": True, "location": location}

    return {"exists": False}


@app.get("/routes")
def get_routes():
    """Get available routes."""
    response = {route: list(destinations.keys()) for route, destinations in ROUTES.items()}
    return {"routes": response}


@app.get("/public-key")
def get_public_key():
    """Get public key for signature verification."""
    pem = PUBLIC_KEY.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return {"public-key": pem.decode("utf-8")}
