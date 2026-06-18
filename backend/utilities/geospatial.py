import math

# Coordinates of key neighborhoods / hubs in Kuala Lumpur, Putrajaya, and Selangor
NEIGHBORHOODS = {
    "Sepang": (2.6908, 101.7410),
    "KLIA (Kuala Lumpur International Airport)": (2.7456, 101.7072),
    "Cyberjaya": (2.9213, 101.6559),
    "Putrajaya": (2.9264, 101.6964),
    "Bukit Bintang": (3.1478, 101.7100),
    "KLCC": (3.1579, 101.7116),
    "Pudu": (3.1340, 101.7130),
    "Petaling Jaya": (3.1279, 101.6444),
    "Subang Jaya": (3.0792, 101.5839),
    "Shah Alam": (3.0738, 101.5183),
    "Klang": (3.0449, 101.4455),
    "Cheras": (3.1026, 101.7408),
    "Bangsar": (3.1292, 101.6687),
    "Ampang": (3.1554, 101.7516),
    "Mont Kiara": (3.1670, 101.6540),
    "Puchong": (3.0333, 101.6167),
    "Sri Petaling": (3.0697, 101.6965),
    "Chow Kit": (3.1636, 101.6980),
    "Damansara": (3.1373, 101.6233),
    "Hartamas": (3.1610, 101.6565),
    "Kuchai": (3.0898, 101.6901),
}

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Calculates the great-circle distance between two points on the Earth's surface
    in kilometers using the Haversine formula.
    """
    # Earth's radius in kilometers
    r = 6371.0
    
    # Convert latitude and longitude from degrees to radians
    lat1_rad = math.radians(lat1)
    lon1_rad = math.radians(lon1)
    lat2_rad = math.radians(lat2)
    lon2_rad = math.radians(lon2)
    
    # Differences in coordinates
    dlat = lat2_rad - lat1_rad
    dlon = lon2_rad - lon1_rad
    
    # Haversine formula
    a = math.sin(dlat / 2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlon / 2)**2
    c = 2 * math.asin(math.sqrt(a))
    
    return r * c

def get_closest_neighborhood(lat: float | None, lng: float | None) -> str:
    """
    Determines the closest neighborhood name based on the Haversine formula.
    If the coordinates are None or the closest match is farther than 50km,
    defaults to 'Kuala Lumpur'.
    """
    if lat is None or lng is None:
        return "Kuala Lumpur"
        
    closest_name = "Kuala Lumpur"
    min_distance = float('inf')
    
    for name, coords in NEIGHBORHOODS.items():
        distance = haversine_distance(lat, lng, coords[0], coords[1])
        if distance < min_distance:
            min_distance = distance
            closest_name = name
            
    # If the distance is more than 50km away, default to generic Kuala Lumpur
    if min_distance > 50.0:
        return "Kuala Lumpur"
        
    return closest_name
