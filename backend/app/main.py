import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings
from app.database import get_supabase, verify_db_connection
from app.routers import auth, convoys, telemetry

app = FastAPI(
    title="ConvoySync API",
    description="Real-Time Convoy Navigation and Multi-Agent Orchestration API",
    version="0.1.0",
)

# Set up CORS middleware to allow cross-origin requests from Flutter (web/mobile clients)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(auth.router)
app.include_router(convoys.router)
app.include_router(telemetry.router)

@app.on_event("startup")
async def startup_event():
    # Initialize the Supabase client connection and verify connectivity
    verify_db_connection()

@app.get("/")
async def root():
    return {
        "message": "Welcome to ConvoySync API",
        "docs_url": "/docs",
        "redoc_url": "/redoc"
    }

if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host=settings.host,
        port=settings.port,
        reload=True
    )
