import math

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Calculate the great-circle distance between two points on the Earth 
    (specified in decimal degrees) using the Haversine formula.
    Returns the distance in kilometers.
    """
    # Earth's radius in kilometers
    R = 6371.0
    
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    
    a = math.sin(delta_phi / 2.0)**2 + \
        math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0)**2
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
    
    return R * c

def bearing_difference(bearing1: float, bearing2: float) -> float:
    """
    Calculates the absolute difference in degrees (0 to 180) between two bearings (0 to 360).
    """
    diff = abs(bearing1 - bearing2) % 360
    if diff > 180:
        diff = 360 - diff
    return diff

def calculate_bearing(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Calculates the bearing (forward azimuth) from point 1 to point 2.
    Returns bearing in degrees (0 to 360).
    """
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_lambda = math.radians(lon2 - lon1)
    
    y = math.sin(delta_lambda) * math.cos(phi2)
    x = math.cos(phi1) * math.sin(phi2) - \
        math.sin(phi1) * math.cos(phi2) * math.cos(delta_lambda)
        
    bearing = math.degrees(math.atan2(y, x))
    return (bearing + 360.0) % 360.0

def point_to_segment_distance_meters(
    lat_p: float, lon_p: float, 
    lat_a: float, lon_a: float, 
    lat_b: float, lon_b: float
) -> tuple[float, float]:
    """
    Calculates the minimum distance in meters from point P to line segment AB,
    using local flat-earth Cartesian projection with point A as origin.
    Also returns the bearing of the segment AB (from A to B) representing the local road direction.
    """
    ref_lat = lat_a
    ref_lon = lon_a
    
    # Conversion factors based on reference latitude
    lat_rad = math.radians(ref_lat)
    m_per_deg_lat = 111320.0
    m_per_deg_lon = 111320.0 * math.cos(lat_rad)
    
    # Project points to local Cartesian coordinates (meters)
    xa, ya = 0.0, 0.0
    xb = (lon_b - ref_lon) * m_per_deg_lon
    yb = (lat_b - ref_lat) * m_per_deg_lat
    xp = (lon_p - ref_lon) * m_per_deg_lon
    yp = (lat_p - ref_lat) * m_per_deg_lat
    
    dx = xb - xa
    dy = yb - ya
    
    segment_len_sq = dx*dx + dy*dy
    segment_bearing = calculate_bearing(lat_a, lon_a, lat_b, lon_b)
    
    if segment_len_sq == 0.0:
        # A and B are the same point
        dist = math.sqrt((xp - xa)**2 + (yp - ya)**2)
        return dist, segment_bearing
        
    # Project point P onto segment AB, clamping to the [0, 1] range to find closest point on segment
    t = ((xp - xa) * dx + (yp - ya) * dy) / segment_len_sq
    t = max(0.0, min(1.0, t))
    
    closest_x = xa + t * dx
    closest_y = ya + t * dy
    
    dist = math.sqrt((xp - closest_x)**2 + (yp - closest_y)**2)
    return dist, segment_bearing

def calculate_cross_track_error_and_road_bearing(
    lat_p: float, lon_p: float, 
    leader_coords: list[tuple[float, float]]
) -> tuple[float, float]:
    """
    Calculates the minimum distance (in meters) from a follower's point P
    to the path defined by leader_coords (list of (lat, lon) tuples representing the leader's trailing path).
    Also returns the bearing (heading) of the closest path segment.
    """
    if not leader_coords:
        return 0.0, 0.0
        
    if len(leader_coords) == 1:
        # Only one point available, return distance to it in meters and default bearing
        dist = haversine_distance(lat_p, lon_p, leader_coords[0][0], leader_coords[0][1]) * 1000.0
        return dist, 0.0
        
    min_dist = float('inf')
    closest_segment_bearing = 0.0
    
    # Evaluate distance to all segments of the leader's trailing history
    for i in range(len(leader_coords) - 1):
        lat_a, lon_a = leader_coords[i]
        lat_b, lon_b = leader_coords[i+1]
        
        dist, bearing = point_to_segment_distance_meters(lat_p, lon_p, lat_a, lon_a, lat_b, lon_b)
        
        if dist < min_dist:
            min_dist = dist
            closest_segment_bearing = bearing
            
    return min_dist, closest_segment_bearing
