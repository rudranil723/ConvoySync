from fastapi import APIRouter

router = APIRouter(prefix="/auth", tags=["auth"])

@router.get("/status")
async def status():
    return {"status": "authenticated"}
