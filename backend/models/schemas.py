from pydantic import BaseModel

class ChatRequest(BaseModel):
    user_id: str
    message: str
    user_lat: float | None = None
    user_lng: float | None = None
    radius_meters: float = 10000.0

class ChatResponse(BaseModel):
    reply: str