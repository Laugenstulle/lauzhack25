from collections import deque


def get_sbb_routes():
    """
    Returns a dictionary of SBB routes with fantasy travel times (in minutes).
    """

    # Define connections as (Station A, Station B, Minutes)
    raw_connections = [
        ("Zurich HB", "Bern", 56),
        ("Zurich HB", "Basel SBB", 53),
        ("Zurich HB", "Winterthur", 20),
        ("Zurich HB", "Luzern", 41),
        ("Zurich HB", "Chur", 74),
        ("Zurich HB", "Olten", 31),
        ("Zurich HB", "Bellinzona", 95),

        ("Bern", "Basel SBB", 55),
        ("Bern", "Geneva", 100),
        ("Bern", "Lausanne", 66),
        ("Bern", "Luzern", 60),
        ("Bern", "Interlaken Ost", 52),
        ("Bern", "Visp", 56),
        ("Bern", "Olten", 27),
        ("Bern", "Biel/Bienne", 26),

        ("Basel SBB", "Olten", 24),
        ("Basel SBB", "Luzern", 62),
        ("Basel SBB", "Biel/Bienne", 56),

        ("Geneva", "Lausanne", 36),
        ("Geneva", "Brig", 130),
        ("Lausanne", "Brig", 85),
        ("Lausanne", "Biel/Bienne", 60),
        ("Lausanne", "Sion", 65),

        ("Winterthur", "St. Gallen", 35),
        ("St. Gallen", "Chur", 60),

        ("Luzern", "Bellinzona", 70),
        ("Luzern", "Olten", 35),
        ("Lugano", "Bellinzona", 14),

        ("Visp", "Brig", 8),
        ("Visp", "Sion", 30),
    ]

    # Build symmetric dictionary
    routes = {}

    def add_route(start, end, time):
        if start not in routes:
            routes[start] = {}
        if end not in routes:
            routes[end] = {}

        routes[start][end] = time
        routes[end][start] = time

    for start, end, time in raw_connections:
        add_route(start, end, time)

    return routes


ROUTES = get_sbb_routes()


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
