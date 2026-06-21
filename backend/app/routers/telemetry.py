import logging
import json
from datetime import datetime
from typing import Dict, List
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query, HTTPException, status
from pydantic import BaseModel, Field, ValidationError

from app.database import get_supabase
from app.services.geo import (
    haversine_distance, 
    bearing_difference, 
    calculate_cross_track_error_and_road_bearing
)

logger = logging.getLogger("uvicorn.error")

router = APIRouter(prefix="/telemetry", tags=["telemetry"])

# Pydantic schema for incoming client telemetry packets
class TelemetryPacket(BaseModel):
    latitude: float = Field(..., ge=-90.0, le=90.0)
    longitude: float = Field(..., ge=-180.0, le=180.0)
    speed: float = Field(..., ge=0.0)
    bearing: float = Field(..., ge=0.0, le=360.0)

# Connection Manager to handle active Websockets grouped by convoy_id
class ConnectionManager:
    def __init__(self):
        # Maps convoy_id -> Dict[profile_id, WebSocket]
        self.active_connections: Dict[str, Dict[str, WebSocket]] = {}

    async def connect(self, convoy_id: str, profile_id: str, websocket: WebSocket) -> bool:
        """
        Accepts the websocket connection and registers the profile to the convoy.
        """
        await websocket.accept()
        if convoy_id not in self.active_connections:
            self.active_connections[convoy_id] = {}
        
        # If the same user connects from a different device, close the previous socket gracefully
        if profile_id in self.active_connections[convoy_id]:
            try:
                old_ws = self.active_connections[convoy_id][profile_id]
                await old_ws.close(code=status.WS_1008_POLICY_VIOLATION, reason="Duplicate connection")
            except Exception:
                pass
                
        self.active_connections[convoy_id][profile_id] = websocket
        logger.info(f"User {profile_id} connected to convoy {convoy_id} WebSocket.")
        return True

    def disconnect(self, convoy_id: str, profile_id: str):
        """
        Deregisters the profile from the convoy connection list.
        """
        if convoy_id in self.active_connections:
            if profile_id in self.active_connections[convoy_id]:
                del self.active_connections[convoy_id][profile_id]
                logger.info(f"User {profile_id} disconnected from convoy {convoy_id}.")
            if not self.active_connections[convoy_id]:
                del self.active_connections[convoy_id]

    async def broadcast_to_convoy(self, convoy_id: str, message: dict, exclude_profile_id: str = None):
        """
        Broadcasts a JSON message to all active users in a convoy, optionally excluding one.
        """
        if convoy_id not in self.active_connections:
            return
            
        targets = list(self.active_connections[convoy_id].items())
        for pid, ws in targets:
            if exclude_profile_id and pid == exclude_profile_id:
                continue
            try:
                await ws.send_json(message)
            except Exception as e:
                logger.error(f"Error sending WebSocket message to {pid} in convoy {convoy_id}: {e}")
                # We do not disconnect immediately to prevent lockups; 
                # cleanup will happen naturally when their connection loop catches the exception.

manager = ConnectionManager()

def verify_convoy_membership(convoy_id: str, profile_id: str) -> bool:
    """
    Checks Supabase database to verify if the profile_id is a member of the convoy_id.
    """
    supabase = get_supabase()
    if supabase is None:
        # Fallback to true in development if DB is not configured, to allow testing routing stubs
        logger.warning("Database client unavailable. Allowing connection by default for verification.")
        return True
    try:
        response = supabase.table("convoy_members")\
            .select("convoy_id")\
            .eq("convoy_id", convoy_id)\
            .eq("profile_id", profile_id)\
            .execute()
        return len(response.data) > 0
    except Exception as e:
        logger.error(f"Database query error during membership check: {e}")
        return False

def get_convoy_leader_and_threshold(convoy_id: str) -> tuple[str, float]:
    """
    Retrieves the convoy's leader_id and alert threshold from the database.
    """
    supabase = get_supabase()
    if supabase is None:
        return None, 1.5
    try:
        response = supabase.table("convoys")\
            .select("leader_id, alert_threshold_km")\
            .eq("id", convoy_id)\
            .execute()
        if response.data:
            leader_id = response.data[0].get("leader_id")
            threshold = response.data[0].get("alert_threshold_km", 1.5)
            return leader_id, threshold
    except Exception as e:
        logger.error(f"Database query error fetching convoy lead configuration: {e}")
    return None, 1.5

def get_leader_trailing_path(convoy_id: str, leader_id: str, limit: int = 10) -> list[tuple[float, float]]:
    """
    Fetches the recent coordinate logs of the leader to construct their path.
    Returns a list of (latitude, longitude) tuples chronologically sorted (oldest to newest).
    """
    supabase = get_supabase()
    if supabase is None or not leader_id:
        return []
    try:
        response = supabase.table("telemetry_logs")\
            .select("latitude, longitude, timestamp")\
            .eq("convoy_id", convoy_id)\
            .eq("profile_id", leader_id)\
            .order("timestamp", desc=True)\
            .limit(limit)\
            .execute()
        if response.data:
            # Sort chronologically ascending (older points first, latest point last)
            sorted_logs = sorted(response.data, key=lambda x: x["timestamp"])
            return [(log["latitude"], log["longitude"]) for log in sorted_logs]
    except Exception as e:
        logger.error(f"Database query error fetching leader logs: {e}")
    return []

def save_telemetry_to_db(convoy_id: str, profile_id: str, packet: TelemetryPacket):
    """
    Saves a telemetry coordinate packet to the database asynchronously.
    Exceptions are caught so that database lag/failure doesn't crash the websocket connection.
    """
    supabase = get_supabase()
    if supabase is None:
        return
    try:
        supabase.table("telemetry_logs").insert({
            "convoy_id": convoy_id,
            "profile_id": profile_id,
            "latitude": packet.latitude,
            "longitude": packet.longitude,
            "speed": packet.speed,
            "bearing": packet.bearing,
            "timestamp": datetime.utcnow().isoformat()
        }).execute()
    except Exception as e:
        logger.error(f"Failed to persist telemetry log to database: {e}")

@router.get("/status")
async def status_check():
    return {
        "status": "active",
        "active_convoys_count": len(manager.active_connections)
    }

@router.websocket("/ws/convoy/{convoy_id}")
async def telemetry_websocket(
    websocket: WebSocket, 
    convoy_id: str, 
    profile_id: str = Query(..., description="The Profile UUID of the connecting user")
):
    # 1. Verify convoy membership before full handshake acceptance
    if not verify_convoy_membership(convoy_id, profile_id):
        logger.warning(f"Connection rejected. User {profile_id} is not a member of convoy {convoy_id}.")
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Not a member of this convoy")
        return

    # 2. Add connection to manager
    connected = await manager.connect(convoy_id, profile_id, websocket)
    if not connected:
        return

    try:
        while True:
            # Receive text message from client (JSON string)
            data_text = await websocket.receive_text()
            
            try:
                # Parse and validate incoming packet using Pydantic
                data_json = json.loads(data_text)
                packet = TelemetryPacket(**data_json)
            except (json.JSONDecodeError, ValidationError) as err:
                # Handle bad formatting gracefully without dropping the socket connection
                logger.warning(f"Invalid telemetry payload from {profile_id}: {err}")
                await websocket.send_json({
                    "error": "invalid_payload",
                    "details": str(err)
                })
                continue

            # Save the coordinates to the database
            save_telemetry_to_db(convoy_id, profile_id, packet)

            # Retrieve convoy configuration
            leader_id, alert_threshold_km = get_convoy_leader_and_threshold(convoy_id)

            # Anomaly evaluation variables
            distance_to_leader_km = 0.0
            cross_track_error_meters = 0.0
            distance_exceeded = False
            wrong_turn = False
            road_bearing = None

            # 3. Calculate distance and cross-track error if the user is a follower
            if leader_id and leader_id != profile_id:
                leader_path = get_leader_trailing_path(convoy_id, leader_id)
                
                if leader_path:
                    # Latest position of leader is the last item in the chronological path
                    leader_lat, leader_lon = leader_path[-1]
                    
                    # Distance between follower and leader (Haversine)
                    distance_to_leader_km = haversine_distance(
                        packet.latitude, packet.longitude, leader_lat, leader_lon
                    )
                    
                    # Calculate cross-track error (meters) and nearest segment bearing (road direction)
                    cross_track_error_meters, road_bearing = calculate_cross_track_error_and_road_bearing(
                        packet.latitude, packet.longitude, leader_path
                    )
                    
                    # Apply threshold evaluation
                    if distance_to_leader_km > alert_threshold_km:
                        distance_exceeded = True
                        
                    # Wrong-turn deviation threshold: CTE > 100 meters AND heading deviation > 45 degrees
                    if cross_track_error_meters > 100.0 and road_bearing is not None:
                        bearing_diff = bearing_difference(packet.bearing, road_bearing)
                        if bearing_diff > 45.0:
                            wrong_turn = True

            # Prepare broadcast message payload
            broadcast_payload = {
                "profile_id": profile_id,
                "latitude": packet.latitude,
                "longitude": packet.longitude,
                "speed": packet.speed,
                "bearing": packet.bearing,
                "timestamp": datetime.utcnow().isoformat(),
                "metrics": {
                    "distance_to_leader_km": round(distance_to_leader_km, 4),
                    "cross_track_error_meters": round(cross_track_error_meters, 2),
                    "road_bearing": round(road_bearing, 1) if road_bearing is not None else None
                },
                "flags": {
                    "distance_exceeded": distance_exceeded,
                    "wrong_turn": wrong_turn
                }
            }

            # 4. Broadcast the telemetry log payload to all other convoy members
            await manager.broadcast_to_convoy(convoy_id, broadcast_payload, exclude_profile_id=profile_id)

    except WebSocketDisconnect:
        # Graceful client exit
        manager.disconnect(convoy_id, profile_id)
    except Exception as e:
        # Catch unforeseen errors during transmission to prevent server crash
        logger.error(f"Uncaught exception in WebSocket loop for user {profile_id}: {e}")
        manager.disconnect(convoy_id, profile_id)
