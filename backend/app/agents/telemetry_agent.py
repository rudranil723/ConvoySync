import logging
from app.database import get_supabase
from app.agents.conductor_agent import generate_regroup_instruction

logger = logging.getLogger("uvicorn.error")

async def process_anomaly_event(convoy_id: str, profile_id: str, telemetry_data: dict):
    """
    Background worker that intercepts an anomaly event, resolves names/coords from the DB,
    requests a safety message from the Conductor Agent, and broadcasts the result.
    """
    try:
        supabase = get_supabase()
        if supabase is None:
            logger.warning("Database unavailable in process_anomaly_event. Using defaults.")
            leader_id = None
            leader_name = "Leader"
            follower_name = "Follower"
            leader_coords = (telemetry_data.get("latitude", 0.0), telemetry_data.get("longitude", 0.0))
            leader_bearing = telemetry_data.get("bearing", 0.0)
        else:
            # 1. Fetch leader_id from convoys table
            try:
                convoys_res = supabase.table("convoys").select("leader_id").eq("id", convoy_id).execute()
                leader_id = convoys_res.data[0].get("leader_id") if convoys_res.data else None
            except Exception as db_err:
                logger.error(f"Error fetching convoy leader: {db_err}")
                leader_id = None
                
            # 2. Fetch leader display name or username
            leader_name = "Leader"
            if leader_id:
                try:
                    res_leader = supabase.table("profiles").select("username, display_name").eq("id", leader_id).execute()
                    if res_leader.data:
                        leader_name = res_leader.data[0].get("display_name") or res_leader.data[0].get("username") or "Leader"
                except Exception as db_err:
                    logger.error(f"Error fetching leader name: {db_err}")
            
            # 3. Fetch follower display name or username
            follower_name = "Follower"
            try:
                res_follower = supabase.table("profiles").select("username, display_name").eq("id", profile_id).execute()
                if res_follower.data:
                    follower_name = res_follower.data[0].get("display_name") or res_follower.data[0].get("username") or "Follower"
            except Exception as db_err:
                logger.error(f"Error fetching follower name: {db_err}")

            # 4. Fetch leader's latest coordinates and bearing
            leader_coords = None
            leader_bearing = telemetry_data.get("bearing", 0.0)
            if leader_id:
                try:
                    res_telemetry = supabase.table("telemetry_logs")\
                        .select("latitude, longitude, bearing")\
                        .eq("convoy_id", convoy_id)\
                        .eq("profile_id", leader_id)\
                        .order("timestamp", desc=True)\
                        .limit(1)\
                        .execute()
                    if res_telemetry.data:
                        leader_coords = (res_telemetry.data[0]["latitude"], res_telemetry.data[0]["longitude"])
                        if res_telemetry.data[0].get("bearing") is not None:
                            leader_bearing = res_telemetry.data[0]["bearing"]
                except Exception as db_err:
                    logger.error(f"Error fetching leader telemetry logs: {db_err}")

            if not leader_coords:
                # Fallback to follower coordinates
                leader_coords = (telemetry_data.get("latitude", 0.0), telemetry_data.get("longitude", 0.0))

        # 5. Determine anomaly type description
        flags = telemetry_data.get("flags", {})
        anomaly_type = "anomaly"
        if flags.get("wrong_turn") and flags.get("distance_exceeded"):
            anomaly_type = "wrong_turn and distance_exceeded"
        elif flags.get("wrong_turn"):
            anomaly_type = "wrong_turn"
        elif flags.get("distance_exceeded"):
            anomaly_type = "distance_exceeded"

        # 6. Generate instruction from Conductor Agent
        generated_string = await generate_regroup_instruction(
            leader_name=leader_name,
            follower_name=follower_name,
            anomaly_type=anomaly_type,
            leader_coords=leader_coords,
            bearing=leader_bearing
        )

        # 7. Formulate target payload and broadcast via WebSocket Connection Manager
        payload = {
            "type": "ai_alert",
            "message": generated_string
        }
        
        logger.info(f"Broadcasting AI alert for convoy {convoy_id}: '{generated_string}'")
        
        # Local import to prevent circular dependency
        from app.routers.telemetry import manager
        await manager.broadcast_to_convoy(convoy_id, payload)
        
    except Exception as e:
        logger.error(f"Error in process_anomaly_event background worker: {e}")
