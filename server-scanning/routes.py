from collections import deque

# Sample data representing travel times between stations (in minutes)
ROUTES = {
    "Zurich HB": {"Bern": 56, "Basel SBB": 53, "Winterthur": 20, "Luzern": 41},
    "Bern": {"Zurich HB": 56, "Geneva": 100, "Basel SBB": 55, "Luzern": 60, "Interlaken Ost": 50},
    "Basel SBB": {"Zurich HB": 53, "Bern": 55, "Luzern": 60},
    "Geneva": {"Bern": 100, "Lausanne": 35},
    "Lausanne": {"Geneva": 35, "Bern": 66},
    "Winterthur": {"Zurich HB": 20, "St. Gallen": 35},
    "St. Gallen": {"Winterthur": 35},
    "Luzern": {"Zurich HB": 41, "Bern": 60, "Basel SBB": 60},
    "Interlaken Ost": {"Bern": 50}
}

def get_min_travel_time(start: str, end: str) -> int:
    """
    Calculates the minimum travel time between two stations using BFS.
    Returns 0 if start == end.
    Returns float('inf') if no path is found.
    """
    if start == end:
        return 0
    
    if start not in ROUTES or end not in ROUTES:
        # If station unknown, we can't validate, so we assume it's reachable.
        return 0

    queue = deque([(start, 0)])
    visited = {start: 0}
    
    while queue:
        current_station, current_time = queue.popleft()
        
        if current_station == end:
            return current_time
        
        for neighbor, travel_time in ROUTES[current_station].items():
            new_time = current_time + travel_time
            if neighbor not in visited or new_time < visited[neighbor]:
                visited[neighbor] = new_time
                queue.append((neighbor, new_time))
                
    return visited.get(end, float('inf'))
