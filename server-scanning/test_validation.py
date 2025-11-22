import os
import tempfile
import sqlite3
import time
import atexit
from uuid import uuid4
from fastapi.testclient import TestClient
from bcrypt import hashpw

# Setup temp DB
temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
temp_db.close()
os.environ['DB_PATH'] = temp_db.name

from main import app

client = TestClient(app)

def get_db_connection():
    return sqlite3.connect(temp_db.name)

def test_validation_logic():
    ticket_id = uuid4()
    
    # 1. First scan at Zurich HB
    response = client.put(f"/register/{ticket_id}", json={"location": "Zurich HB"})
    assert response.status_code == 200
    data = response.json()
    assert data["suspicious"] is False
    assert data["location"] == "Zurich HB"

    # 2. Suspicious scan: Winterthur is 20 mins away.
    # We simulate that the first scan happened only 5 minutes ago.
    # We need to update the DB entry for this ticket.
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Find the hashed ticket ID
    cursor.execute('SELECT id FROM tickets')
    rows = cursor.fetchall()
    target_hash = None
    for row in rows:
        if hashpw(ticket_id.bytes, row[0].encode('utf-8')) == row[0].encode('utf-8'):
            target_hash = row[0]
            break
    
    assert target_hash is not None
    
    # Update last_scan_time to 5 minutes ago
    five_mins_ago = time.time() - (5 * 60)
    cursor.execute('UPDATE tickets SET last_scan_time = ? WHERE id = ?', (five_mins_ago, target_hash))
    conn.commit()
    
    # Scan at Winterthur
    response = client.put(f"/register/{ticket_id}", json={"location": "Winterthur"})
    assert response.status_code == 200
    data = response.json()
    assert data["suspicious"] is True
    assert "Suspicious travel detected" in data["message"]

    # 3. Valid scan: Bern is 60 mins from Zurich (where we were at step 1) 
    # BUT wait, step 2 updated the location to Winterthur!
    # So now we are at Winterthur.
    # Let's go to St. Gallen (35 mins from Winterthur).
    # We simulate that the last scan (at Winterthur) was 40 minutes ago.
    
    forty_mins_ago = time.time() - (40 * 60)
    cursor.execute('UPDATE tickets SET last_scan_time = ? WHERE id = ?', (forty_mins_ago, target_hash))
    conn.commit()
    
    response = client.put(f"/register/{ticket_id}", json={"location": "St. Gallen"})
    assert response.status_code == 200
    data = response.json()
    assert data["suspicious"] is False
    
    conn.close()

def test_unknown_station():
    ticket_id = uuid4()
    # Register at unknown station
    response = client.put(f"/register/{ticket_id}", json={"location": "Atlantis"})
    assert response.status_code == 200
    assert response.json()["suspicious"] is False
    
    # Register again at another unknown station immediately
    response = client.put(f"/register/{ticket_id}", json={"location": "El Dorado"})
    assert response.status_code == 200
    assert response.json()["suspicious"] is False

def cleanup():
    try:
        client.close()
        os.unlink(temp_db.name)
    except (PermissionError, FileNotFoundError):
        pass

atexit.register(cleanup)

if __name__ == "__main__":
    test_validation_logic()
    test_unknown_station()
    print("All validation tests passed!")
