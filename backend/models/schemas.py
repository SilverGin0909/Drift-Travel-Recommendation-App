from typing import Optional
from pydantic import BaseModel

class ChatRequest(BaseModel):
    user_id: str
    session_id: str
    message: str
    user_lat: float | None = None
    user_lng: float | None = None
    radius_meters: float = 10000.0
    prefs_context: Optional[str] = None

class ChatResponse(BaseModel):
    reply: str