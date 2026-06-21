import math
import logging
from google import genai
from google.genai import types
from app.config import settings

logger = logging.getLogger("uvicorn.error")

def project_coordinates_miles_ahead(lat: float, lon: float, bearing: float, miles: float = 2.0) -> tuple[float, float]:
    """
    Projects latitude and longitude coordinates a specified distance (in miles) 
    along a given bearing (in degrees).
    """
    # Convert miles to kilometers: 1 mile ≈ 1.60934 km
    d = miles * 1.60934
    # Earth's radius in kilometers
    R = 6371.0
    
    ad = d / R
    bearing_rad = math.radians(bearing)
    lat_rad = math.radians(lat)
    lon_rad = math.radians(lon)
    
    lat2_rad = math.asin(
        math.sin(lat_rad) * math.cos(ad) + 
        math.cos(lat_rad) * math.sin(ad) * math.cos(bearing_rad)
    )
    
    # Calculate difference in longitude
    lon2_rad = lon_rad + math.atan2(
        math.sin(bearing_rad) * math.sin(ad) * math.cos(lat_rad),
        math.cos(ad) - math.sin(lat_rad) * math.sin(lat2_rad)
    )
    
    # Standardize longitude to -180 to +180 degrees range
    lon2_deg = (math.degrees(lon2_rad) + 540) % 360 - 180
    
    return math.degrees(lat2_rad), lon2_deg

async def mock_google_places_api(lat: float, lon: float, query: str = "amenities") -> dict:
    """
    Mocks a Google Places search for safe pull-over locations (e.g. gas stations, cafés)
    around the projected coordinate.
    """
    mock_amenities = [
        {"name": "Shell Gas Station & Convenience Store", "address": "1042 Interstate Hwy, Route 66"},
        {"name": "Starbucks Coffee", "address": "782 Highway Junction Dr"},
        {"name": "Chevron Travel Center", "address": "205 Express Exit Way"},
        {"name": "Highway Scenic Rest Stop", "address": "Mile Marker 142, Northbound"},
        {"name": "Sunrise Roadside Diner", "address": "12 Country Road"}
    ]
    # Pick an amenity deterministically based on coordinates to keep testing consistent
    index = int(abs(lat + lon) * 1000) % len(mock_amenities)
    amenity = mock_amenities[index]
    
    logger.info(f"Mocked Google Places API call: Found '{amenity['name']}' near ({lat:.4f}, {lon:.4f})")
    return {
        "name": amenity["name"],
        "address": amenity["address"],
        "latitude": lat,
        "longitude": lon
    }

async def generate_regroup_instruction(
    leader_name: str, 
    follower_name: str, 
    anomaly_type: str, 
    leader_coords: tuple[float, float] | list[float], 
    bearing: float
) -> str:
    """
    Suggests a regroup location using a mock Google Places call, then sends
    a request to Gemini 1.5 Flash to generate a TTS-optimized alert instruction.
    """
    # Ensure leader_coords is a tuple of (lat, lon)
    if isinstance(leader_coords, list):
        if len(leader_coords) > 0:
            if isinstance(leader_coords[0], (list, tuple)):
                lat, lon = leader_coords[-1]
            else:
                lat, lon = leader_coords[0], leader_coords[1]
        else:
            lat, lon = 0.0, 0.0
    elif isinstance(leader_coords, tuple):
        lat, lon = leader_coords
    else:
        lat, lon = 0.0, 0.0
        
    try:
        # Project 2 miles ahead
        proj_lat, proj_lon = project_coordinates_miles_ahead(lat, lon, bearing, miles=2.0)
        
        # Call mock Places API
        amenity = await mock_google_places_api(proj_lat, proj_lon)
        location_name = amenity["name"]
        
        # Fallback if API key is missing
        if not settings.gemini_api_key:
            logger.warning("GEMINI_API_KEY is not configured. Falling back to default safety announcement.")
            if anomaly_type == "wrong_turn":
                return f"Safety notice: follower {follower_name} has made a wrong turn. Please regroup at {location_name} two miles ahead."
            else:
                return f"Safety notice: follower {follower_name} is lagging behind. Please slow down and regroup at {location_name} two miles ahead."

        client = genai.Client(api_key=settings.gemini_api_key)
        
        prompt = (
            f"Convoy Alert!\n"
            f"Convoy Leader: {leader_name}\n"
            f"Lagging/Off-route Follower: {follower_name}\n"
            f"Anomaly Type: {anomaly_type}\n"
            f"Safe pull-over spot found 2 miles ahead: {location_name} (Address: {amenity['address']})\n"
            f"Write a voice warning alert to play in the convoy riders' helmet communication intercoms."
        )
        
        response = client.models.generate_content(
            model='gemini-1.5-flash',
            contents=prompt,
            config=types.GenerateContentConfig(
                system_instruction=(
                    "You are a calm, elite motorcycle helmet intercom assistant. "
                    "Analyze the convoy anomaly. Output a single, highly concise sentence optimized "
                    "for Text-to-Speech engine playback. Do not use any markdown formatting, asterisks, or emojis."
                )
            )
        )
        return response.text.strip()
        
    except Exception as e:
        logger.error(f"Failed to generate regroup instruction in Conductor Agent: {e}")
        return f"Safety alert. Follower {follower_name} is off course. Regroup at nearest service station."
