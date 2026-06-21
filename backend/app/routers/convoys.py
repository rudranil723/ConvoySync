from fastapi import APIRouter

router = APIRouter(prefix="/convoys", tags=["convoys"])

@router.get("/")
async def list_convoys():
    return {"convoys": []}
