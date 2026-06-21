from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    supabase_url: str = ""
    supabase_key: str = ""
    google_places_api_key: str = ""
    gemini_api_key: str = ""
    
    host: str = "0.0.0.0"
    port: int = 8000

    # Load from a .env file in the backend directory
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

settings = Settings()
