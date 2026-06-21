import logging
from supabase import create_client, Client
from app.config import settings

logger = logging.getLogger("uvicorn.error")

supabase: Client = None

def get_supabase() -> Client:
    """
    Returns the initialized Supabase client singleton, creating it if it doesn't exist yet.
    """
    global supabase
    if supabase is not None:
        return supabase
        
    if not settings.supabase_url or not settings.supabase_key:
        logger.warning("Supabase URL or Key is missing from configuration. Database operations will fail.")
        return None
        
    try:
        supabase = create_client(settings.supabase_url, settings.supabase_key)
        logger.info("Supabase client initialized successfully.")
        return supabase
    except Exception as e:
        logger.error(f"Failed to initialize Supabase client: {e}")
        return None

def verify_db_connection() -> bool:
    """
    Verifies the connection to Supabase by executing a lightweight query.
    Returns True if connection is healthy, False otherwise.
    """
    client = get_supabase()
    if client is None:
        return False
    try:
        # Query profiles table with limit 1 to test basic select connectivity
        client.table("profiles").select("id").limit(1).execute()
        logger.info("Supabase database connection verified successfully.")
        return True
    except Exception as e:
        logger.error(f"Supabase database connection verification failed: {e}")
        return False
