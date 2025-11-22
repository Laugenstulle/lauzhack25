import sqlite3
import os
import time
from fastapi import FastAPI, Body
from uuid import UUID
from bcrypt import hashpw, gensalt
from pydantic import BaseModel
from routes import get_min_travel_time

app = FastAPI()

db_path = os.getenv('DB_PATH', 'tickets.db')
db_connection = sqlite3.connect(db_path, check_same_thread=False)
db_cursor = db_connection.cursor()

db_cursor.execute('''
    CREATE TABLE IF NOT EXISTS tickets (
        id TEXT PRIMARY KEY,
        location TEXT,
        last_scan_time REAL
    )
''')


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
