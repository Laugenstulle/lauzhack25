import os
import tempfile
import sqlite3
import atexit
from uuid import uuid4
from fastapi.testclient import TestClient

temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
temp_db.close()
os.environ['DB_PATH'] = temp_db.name

from main import app

client = TestClient(app)


# Testfunktion
def test_register_ticket():
    ticket_id = uuid4()
    response = client.put(f"/register/{ticket_id}")

    # Überprüfen, ob die Antwort erfolgreich ist
    assert response.status_code == 200
    data = response.json()
    assert "message" in data
    assert data["ticket"] == str(ticket_id)

    # Überprüfen, ob der Hash in der Datenbank gespeichert wurde
    db_connection = sqlite3.connect(temp_db.name)
    db_cursor = db_connection.cursor()
    db_cursor.execute('SELECT id FROM tickets')

    result = db_cursor.fetchone()
    assert result is not None
    assert len(result[0]) > 0
    db_connection.close()

    print("Test erfolgreich!")


def cleanup():
    try:
        client.close()
        os.unlink(temp_db.name)
    except (PermissionError, FileNotFoundError):
        pass  # Ignorieren, wenn die Datei nicht gelöscht werden kann


# Cleanup am Programmende
atexit.register(cleanup)

if __name__ == "__main__":
    test_register_ticket()
